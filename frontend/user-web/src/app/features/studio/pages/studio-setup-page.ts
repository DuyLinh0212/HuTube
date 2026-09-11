import { Component } from '@angular/core';
import { ChannelCreatePage } from '../../channel/channel-create-page';

@Component({
  selector: 'app-studio-setup-page',
  imports: [ChannelCreatePage],
  template: `<section class="setup-shell"><div class="setup-note"><span>Creator Studio</span><h1>Thiết lập kênh trước khi bắt đầu</h1><p>Thông tin này chỉ được hỏi một lần. Sau khi tạo kênh, Studio sẽ mở thẳng bảng điều khiển.</p></div><app-channel-create-page [studioMode]="true" /></section>`,
  styles: [`.setup-shell{max-width:1080px;margin:auto;padding:32px 20px}.setup-note{max-width:720px;margin:0 auto 18px}.setup-note span{color:var(--primary);font-size:.72rem;font-weight:800;letter-spacing:.12em;text-transform:uppercase}.setup-note h1{margin:6px 0;font-size:1.7rem}.setup-note p{margin:0;color:var(--text-muted);line-height:1.55}`]
})
export class StudioSetupPage {}
