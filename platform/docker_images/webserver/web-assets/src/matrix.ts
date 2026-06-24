export type MatrixRaw = {
  last_updated: number | null;
  update_frequency: number | null;
  connectivity: Record<string, Record<string, boolean>>;
  validity: Record<string, Record<string, boolean>>;
};

export type ReachabilityStatus = "valid" | "invalid" | "failure" | "missing";

export type StatusInfo = {
  label: string;
  description: string;
  color: string;
  textColor: string;
};

export const STATUS_INFO: Record<ReachabilityStatus, StatusInfo> = {
  valid: {
    label: "Reachable, valid path",
    description: "The ping succeeded and the AS-level path is valid.",
    color: "#56c157",
    textColor: "#111827"
  },
  invalid: {
    label: "Reachable, invalid path",
    description: "The ping succeeded, but the AS-level path violates policy.",
    color: "#f0ad4e",
    textColor: "#111827"
  },
  failure: {
    label: "Not reachable",
    description: "The ping did not succeed.",
    color: "#d5605e",
    textColor: "#ffffff"
  },
  missing: {
    label: "No data",
    description: "No matrix value is available for this pair.",
    color: "#d4d4d4",
    textColor: "#404040"
  }
};

export function sortAsns(asns: string[]): string[] {
  return [...asns].sort((a, b) => Number(a) - Number(b));
}

export function normalizeAsn(value: string): string {
  return value.trim().replace(/^as/i, "");
}

export function getStatus(
  matrix: MatrixRaw | null,
  sourceAsn: string,
  destinationAsn: string
): ReachabilityStatus {
  if (!matrix || !sourceAsn || !destinationAsn) {
    return "missing";
  }

  const connected = matrix.connectivity[sourceAsn]?.[destinationAsn];
  if (connected === undefined) {
    return "missing";
  }
  if (!connected) {
    return "failure";
  }
  if (matrix.validity[sourceAsn]?.[destinationAsn] === false) {
    return "invalid";
  }
  return "valid";
}

export function summarizeRow(
  matrix: MatrixRaw | null,
  sourceAsn: string,
  destinations: string[]
): Record<ReachabilityStatus, number> {
  const counts: Record<ReachabilityStatus, number> = {
    valid: 0,
    invalid: 0,
    failure: 0,
    missing: 0
  };

  for (const destinationAsn of destinations) {
    counts[getStatus(matrix, sourceAsn, destinationAsn)] += 1;
  }

  return counts;
}
