import { Component, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ContentService, VideoCard } from '../../core/content.service';

@Component({
  selector: 'app-home-page', imports: [RouterLink, DatePipe],
  template: `<main id="main-content" class="feed"><header><div><span>HuTube Picks</span><h1>{{ explore ? 'Khám phá' : 'Video dành cho bạn' }}</h1><p>{{ explore ? 'Khám phá video công khai theo danh mục và xu hướng.' : 'Nội dung mới và nổi bật từ cộng đồng HuTube.' }}</p></div></header>
    @if (explore) { <div class="feed-filters" aria-label="Bộ lọc khám phá"><label>Sắp xếp<select [value]="selectedSort()" (change)="changeSort($any($event.target).value)"><option value="newest">Mới nhất</option><option value="popular">Phổ biến</option><option value="trending">Thịnh hành</option></select></label><label>Danh mục<select [value]="selectedCategoryId()" (change)="changeCategory($any($event.target).value)"><option value="">Tất cả danh mục</option>@for (category of categories(); track category.categoryId) { <option [value]="category.categoryId">{{ category.name }}</option> }</select></label></div> }
    @if (loading()) { <p class="state">Đang tải video…</p> } @else if (error()) { <p class="state error">{{ error() }}</p> } @else {
      <section class="grid" aria-label="Danh sách video">@for (video of videos(); track video.videoId) {
        <a class="card" [routerLink]="['/watch', video.videoId]"><div class="thumb">@if(video.thumbnailUrl){<img [src]="video.thumbnailUrl" alt=""/>}@else{<span>▶</span>}<time>{{ duration(video.duration) }}</time></div>
          <div class="copy"><h2>{{ video.title }}</h2><p>{{ video.channelName }}</p><small>{{ video.views }} lượt xem · {{ video.publishedAt | date:'dd/MM/yyyy' }}</small></div></a>
      } @empty { <p class="state">Chưa có video nào.</p> }</section> }
  </main>`,
  styles: [`.feed{max-width:1320px;margin:auto;padding:32px 28px}.feed header span{color:var(--primary);font-size:.7rem;font-weight:850;letter-spacing:.14em;text-transform:uppercase}.feed h1{margin:5px 0 4px;font-size:clamp(1.6rem,3vw,2.4rem)}.feed header p,.card p,.card small,.state{color:var(--text-muted)}.feed-filters{display:flex;flex-wrap:wrap;gap:12px;margin-top:22px;padding:12px 14px;border:1px solid var(--line);border-radius:12px;background:var(--surface);color:var(--text-muted);font-size:.8rem}.feed-filters label{display:flex;align-items:center;gap:8px}.feed-filters select{padding:8px 10px;border:1px solid var(--line);border-radius:8px;background:var(--canvas);color:var(--ink)}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:24px 18px;margin-top:28px}.card{color:inherit;text-decoration:none}.thumb{position:relative;display:grid;aspect-ratio:16/9;place-items:center;overflow:hidden;border-radius:14px;background:linear-gradient(135deg,var(--primary-soft),var(--card-hover));font-size:2rem}.thumb img{width:100%;height:100%;object-fit:cover;transition:transform .2s}.card:hover img{transform:scale(1.03)}.thumb time{position:absolute;right:8px;bottom:8px;padding:3px 6px;border-radius:5px;background:rgba(0,0,0,.8);color:#fff;font-size:.68rem}.copy h2{margin:11px 0 5px;font-size:.94rem;line-height:1.35}.copy p,.copy small{margin:0;font-size:.76rem}.error{color:var(--danger)}@media(max-width:600px){.feed{padding:22px 14px}.feed-filters{align-items:stretch;flex-direction:column}.feed-filters label{justify-content:space-between}.feed-filters select{min-width:190px}.grid{grid-template-columns:1fr}}`]
})
export class HomePage {
  private readonly content = inject(ContentService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  readonly videos = signal<VideoCard[]>([]);
  readonly categories = signal<{ categoryId: string; name: string }[]>([]);
  readonly selectedCategoryId = signal('');
  readonly selectedSort = signal('newest');
  readonly loading = signal(true);
  readonly error = signal('');
  explore = location.pathname.includes('explore');
  constructor(){
    const params = this.route.snapshot.queryParamMap;
    this.selectedCategoryId.set(params.get('categoryId') ?? '');
    this.selectedSort.set(params.get('sort') ?? (this.explore ? 'newest' : 'popular'));
    if (this.explore) this.content.categories().subscribe({ next: value => this.categories.set(value ?? []), error: () => {} });
    this.load();
  }
  load(){
    this.loading.set(true);
    const params = this.route.snapshot.queryParamMap;
    this.content.feed(this.explore ? 'explore' : 'home', 1, 20, this.selectedCategoryId() || undefined, params.get('q') || undefined, this.selectedSort()).subscribe({next:value=>{this.videos.set(value.items ?? []);this.error.set('');this.loading.set(false)},error:(reason: unknown)=>{this.videos.set([]);this.error.set(reason instanceof HttpErrorResponse && reason.status === 404 ? '' : 'Không thể tải danh sách video.');this.loading.set(false)}})
  }
  changeSort(value: string){ this.selectedSort.set(value || 'newest'); this.updateQuery(); this.load(); }
  changeCategory(value: string){ this.selectedCategoryId.set(value); this.updateQuery(); this.load(); }
  private updateQuery(){ void this.router.navigate([], { relativeTo: this.route, queryParams: { sort: this.selectedSort(), categoryId: this.selectedCategoryId() || null }, queryParamsHandling: 'merge', replaceUrl: true }); }
  duration(value:number){return `${Math.floor(value/60)}:${String(value%60).padStart(2,'0')}`}
}
