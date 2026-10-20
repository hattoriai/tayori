// The packages of deps/ the admin bundles, which ship no types.

declare module "phoenix" {
  export const Socket: unknown;
  export const LongPoll: unknown;
}

declare module "phoenix_mountable" {
  export function connect(options: Record<string, unknown>): unknown;
  export function path(relative: string): string;
}

declare module "phoenix_live_view" {
  export class LiveSocket {
    constructor(path: string, socket: unknown, opts: Record<string, unknown>);
    connect(): void;
  }
}

declare module "kotoba" {
  export const Kotoba: object;
}

declare module "koyomi" {
  export const Koyomi: object;
}
