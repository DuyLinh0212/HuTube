import { DatePipe, DecimalPipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { StudioDataService } from '../../../core/studio-data.service';

@Component({
  selector: 'app-studio-overview-page',
  imports: [RouterLink, DatePipe, DecimalPipe],
  template: `<main class="page"><header><div><h1>Tổng quan</h1><p>Dữ liệu trực tiếp của kênh {{data.channel()?.name}}</p></div><a routerLink="/studio/upload">+ Tải video lên</a></header>@if(data.loading()){<p>Đang tải…</p>}@else{<section class="stats"><article><span>Người đăng ký</span><strong>{{data.channel()?.subscriberCount|number}}</strong></article><article><span>Lượt xem</span><strong>{{data.views()|number}}</strong></article><article><span>Thời lượng xem ước tính</span><strong>{{data.watchSeconds()/3600|number:'1.0-1'}} giờ</strong></article><article><span>Bình luận</span><strong>{{data.comments()|number}}</strong></article></section><section class="panel"><div class="panel-head"><h2>Video gần nhất</h2><a routerLink="/studio/content">Xem tất cả</a></div>@if(data.videos()[0];as v){<a class="video" [routerLink]="['/watch',v.videoId]"><div class="thumb">@if(v.thumbnailUrl){<img [src]="v.thumbnailUrl" alt=""/>}@else{▶}</div><div><h3>{{v.title}}</h3><p>{{v.createdAt|date:'dd/MM/yyyy'}} · {{v.visibility}} · {{v.status}}</p><span>{{v.stats.views}} lượt xem · {{v.stats.likes}} lượt thích · {{v.stats.comments}} bình luận</span></div></a>}@else{<p>Chưa có video. Hãy tải video đầu tiên của bạn.</p>}</section>}</main>`,
  styles: [`.page{max-width:1200px;margin:auto;padding:32px 24px}header,.panel-head{display:flex;align-items:center;justify-content:space-between;gap:16px}h1{margin:0}header p,.video p{color:var(--text-muted)}header a,.panel a{color:var(--primary);font-weight:700;text-decoration:none}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:24px 0}.stats article,.panel{padding:20px;border:1px solid var(--line);border-radius:14px;background:var(--surface)}.stats article{display:grid;gap:8px}.stats span{color:var(--text-muted);font-size:.8rem}.stats strong{font-size:1.4rem}.video{display:flex;gap:16px;align-items:center;padding-top:14px;color:inherit;text-decoration:none}.thumb{display:grid;width:180px;aspect-ratio:16/9;place-items:center;overflow:hidden;border-radius:10px;background:var(--canvas)}.thumb img{width:100%;height:100%;object-fit:cover}.video h3{margin:0}@media(max-width:800px){.stats{grid-template-columns:repeat(2,1fr)}.video{align-items:flex-start;flex-direction:column}.thumb{width:100%}}`]
})
export class StudioOverviewPage implements OnInit {
  readonly data = inject(StudioDataService);

  ngOnInit() {
    this.data.load();
  }
}
