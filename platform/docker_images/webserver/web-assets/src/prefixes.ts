const IPV4_BITS = 32;


export function prefixForIndex(index: number, depth: number): string {
  const blockSize = 2 ** (IPV4_BITS - depth);
  const address = index * blockSize;
  return `${formatIpv4(address)}/${depth}`;
}

export function generateLeafPrefixes(depth: number, _count: number): string[] {
  const capacity = 2 ** depth;
  return Array.from({ length: capacity }, (_, index) => prefixForIndex(index, depth));
}

export function generateInternalPrefixes(depth: number): string[] {
  const prefixes: string[] = [];

  for (let level = 0; level < depth; level += 2) {
    for (let index = 0; index < 2 ** level; index += 1) {
      prefixes.push(prefixForIndex(index, level));
    }
  }

  return prefixes;
}

function formatIpv4(address: number): string {
  return [
    Math.floor(address / 2 ** 24) % 256,
    Math.floor(address / 2 ** 16) % 256,
    Math.floor(address / 2 ** 8) % 256,
    address % 256
  ].join(".");
}
