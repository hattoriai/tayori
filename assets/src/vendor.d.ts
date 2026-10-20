// The packages of deps/ the admin bundles, which ship no types
// (phoenix_mountable ships its own: see tsconfig.json).

declare module "phoenix" {
  export const Socket: unknown;
  export const LongPoll: unknown;
}

declare module "phoenix_live_view" {
  export class LiveSocket {
    constructor(path: string, socket: unknown, opts: object);
    connect(): void;
  }
}

declare module "kotoba" {
  export const Kotoba: object;
}

declare module "koyomi" {
  export const Koyomi: object;
}
