export function suggestChannelHandle(name: string, suffix: string): string {
  const base = name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'dalitu';
  return `${base.slice(0, 41).replace(/-+$/g, '')}-${suffix}`;
}
