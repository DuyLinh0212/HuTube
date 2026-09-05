import { Component } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';
import { ADMIN_APP } from './core/runtime-config';
@Component({ selector: 'app-root', imports: [RouterLink, RouterOutlet], templateUrl: './app.html' })
export class App { readonly admin = ADMIN_APP; }
