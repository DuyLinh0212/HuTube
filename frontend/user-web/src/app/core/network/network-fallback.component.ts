import { Component, inject } from '@angular/core';
import { TranslatePipe } from '../translate.pipe';
import { NetworkStatusService } from './network-status.service';

@Component({
  selector: 'app-network-fallback',
  imports: [TranslatePipe],
  templateUrl: './network-fallback.component.html',
  styleUrl: './network-fallback.component.scss',
})
export class NetworkFallbackComponent {
  readonly network = inject(NetworkStatusService);

  retry(): void {
    void this.network.checkConnection();
  }
}
