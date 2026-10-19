import os
import sys
import torch
import numpy as np
from pathlib import Path
from sklearn.metrics import accuracy_score, f1_score, precision_recall_fscore_support
from transformers import TrainingArguments, Trainer, EarlyStoppingCallback

# Fix UTF-8 output on Windows terminal
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

# Thêm đường dẫn gốc vào sys.path để import src
CURRENT_DIR = Path(__file__).resolve().parent
ROOT_DIR = CURRENT_DIR.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from src.config import (
    PRETRAINED_MODEL_NAME,
    BEST_MODEL_DIR,
    OUTPUTS_DIR,
    TRAINING_CONFIG,
    NUM_LABELS,
    ID2LABEL,
    LABEL2ID
)
from src.dataset import load_vsmec_data, VSMECDataset
from src.model import get_tokenizer, get_model

def compute_metrics(eval_pred):
    """Tính các chỉ số đánh giá: Accuracy, F1 Macro và F1 Weighted."""
    logits, labels = eval_pred
    preds = np.argmax(logits, axis=-1)

    acc = accuracy_score(labels, preds)
    f1_macro = f1_score(labels, preds, average="macro", zero_division=0)
    f1_weighted = f1_score(labels, preds, average="weighted", zero_division=0)

    precision, recall, _, _ = precision_recall_fscore_support(labels, preds, average="macro", zero_division=0)

    return {
        "accuracy": acc,
        "f1_macro": f1_macro,
        "f1_weighted": f1_weighted,
        "precision_macro": precision,
        "recall_macro": recall
    }

def main():
    print("=" * 70)
    print("HUẤN LUYỆN MÔ HÌNH NHẬN DIỆN CẢM XÚC TIẾNG VIỆT (UIT-VSMEC)")
    print(f"Mô hình nền: {PRETRAINED_MODEL_NAME}")
    print("=" * 70)

    has_cuda = torch.cuda.is_available()
    device_name = torch.cuda.get_device_name(0) if has_cuda else "CPU"
    print(f"[*] Thiết bị huấn luyện: {device_name}")
    if has_cuda:
        total_vram = torch.cuda.get_device_properties(0).total_memory / (1024 ** 3)
        print(f"[*] VRAM khả dụng: {total_vram:.2f} GB")

    # 1. Tải tokenizer và model
    print("\n[1/5] Đang khởi tạo Tokenizer và PhoBERT Model...")
    tokenizer = get_tokenizer(PRETRAINED_MODEL_NAME)
    model = get_model(PRETRAINED_MODEL_NAME, num_labels=NUM_LABELS)

    # 2. Tải dữ liệu UIT-VSMEC
    print("\n[2/5] Đang nạp dữ liệu train và validation...")
    train_raw = load_vsmec_data("train")
    val_raw = load_vsmec_data("validation")

    print(f"[*] Số lượng mẫu Train: {len(train_raw)}")
    print(f"[*] Số lượng mẫu Validation: {len(val_raw)}")

    train_dataset = VSMECDataset(train_raw, tokenizer, max_length=TRAINING_CONFIG["max_length"])
    val_dataset = VSMECDataset(val_raw, tokenizer, max_length=TRAINING_CONFIG["max_length"])

    # 3. Tính Class Weights và cấu hình TrainingArguments
    print("\n[3/5] Tính Class Weights và thiết lập Training Arguments...")
    from sklearn.utils.class_weight import compute_class_weight
    import torch.nn as nn

    train_labels = [item["Emotion"] for item in train_raw]
    computed_weights = compute_class_weight(
        class_weight="balanced",
        classes=np.array(EMOTION_LABELS),
        y=train_labels
    )
    class_weights_tensor = torch.tensor(computed_weights, dtype=torch.float)

    use_fp16 = has_cuda and TRAINING_CONFIG.get("fp16", True)

    training_args = TrainingArguments(
        output_dir=str(OUTPUTS_DIR),
        eval_strategy=TRAINING_CONFIG["eval_strategy"],
        save_strategy=TRAINING_CONFIG["save_strategy"],
        learning_rate=TRAINING_CONFIG["learning_rate"],
        lr_scheduler_type=TRAINING_CONFIG.get("lr_scheduler_type", "cosine"),
        per_device_train_batch_size=TRAINING_CONFIG["per_device_train_batch_size"],
        per_device_eval_batch_size=TRAINING_CONFIG["per_device_eval_batch_size"],
        gradient_accumulation_steps=TRAINING_CONFIG["gradient_accumulation_steps"],
        num_train_epochs=TRAINING_CONFIG["num_train_epochs"],
        weight_decay=TRAINING_CONFIG["weight_decay"],
        warmup_steps=TRAINING_CONFIG.get("warmup_steps", 150),
        fp16=use_fp16,
        logging_steps=TRAINING_CONFIG["logging_steps"],
        save_total_limit=TRAINING_CONFIG["save_total_limit"],
        load_best_model_at_end=TRAINING_CONFIG["load_best_model_at_end"],
        metric_for_best_model=TRAINING_CONFIG["metric_for_best_model"],
        greater_is_better=TRAINING_CONFIG["greater_is_better"],
        report_to="none"  # Không cần wandb
    )

    class WeightedTrainer(Trainer):
        def compute_loss(self, model, inputs, return_outputs=False, **kwargs):
            labels = inputs.get("labels")
            outputs = model(**inputs)
            logits = outputs.get("logits")
            loss_fct = nn.CrossEntropyLoss(weight=class_weights_tensor.to(model.device))
            loss = loss_fct(logits.view(-1, self.model.config.num_labels), labels.view(-1))
            return (loss, outputs) if return_outputs else loss

    # 4. Huấn luyện với Weighted Trainer
    trainer = WeightedTrainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=val_dataset,
        compute_metrics=compute_metrics,
        callbacks=[EarlyStoppingCallback(early_stopping_patience=3)]
    )

    print("\n[4/5] Bắt đầu quá trình huấn luyện (Fine-tuning)...")
    train_result = trainer.train()

    print("\n[5/5] Đang lưu mô hình tốt nhất (Best Checkpoint)...")
    BEST_MODEL_DIR.mkdir(parents=True, exist_ok=True)
    trainer.save_model(str(BEST_MODEL_DIR))
    tokenizer.save_pretrained(str(BEST_MODEL_DIR))

    print(f"\n[+] Huấn luyện thành công!")
    print(f"[+] Model và Tokenizer đã được lưu tại: {BEST_MODEL_DIR}")
    print(f"[+] Metrics cuối cùng:")
    for k, v in train_result.metrics.items():
        print(f"    - {k}: {v}")

if __name__ == "__main__":
    main()
