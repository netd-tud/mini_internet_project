import { useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import {
  InteractiveHilbert,
  useControlledHilbert,
  type RenderFunction
} from "@netd-tud/hilby";

import {
  getStatus,
  normalizeAsn,
  sortAsns,
  STATUS_INFO,
  summarizeRow,
  type MatrixRaw,
  type ReachabilityStatus
} from "./matrix";
import {
  calculateLeafDepth,
  generateInternalPrefixes,
  generateLeafPrefixes
} from "./prefixes";

const TOP_PREFIX = "0.0.0.0/0";
const RESERVED_ASNS = new Set(["0", "127"]);
type AggregateReachability = {
  connectivity: number | null;
  reachable: number;
  total: number;
};

const baseRender: RenderFunction = (_prefix, _long, _netmask, config) => {
  config.style.backgroundColor = "#d4d4d4";
  config.style.color = "#404040";
  config.style.display = "flex";
  config.style.alignItems = "center";
  config.style.justifyContent = "center";
  config.style.textAlign = "center";
  config.style.cursor = "pointer";
};

function App() {
  const [matrix, setMatrix] = useState<MatrixRaw | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [asnInput, setAsnInput] = useState("");
  const initializedAsnInput = useRef(false);

  const [
    hilbertStore,
    { clearAllPrefixes, setPrefixSplit },
    _zoomManipulation,
    useHoverPrefix
  ] = useControlledHilbert();
  const hoverPrefix = useHoverPrefix();

  useEffect(() => {
    let cancelled = false;

    async function loadMatrix() {
      try {
        setLoading(true);
        const response = await fetch("/matrix?raw", { cache: "no-store" });
        if (!response.ok) {
          throw new Error(`Matrix request failed with HTTP ${response.status}`);
        }
        const data = (await response.json()) as MatrixRaw;
        if (!cancelled) {
          setMatrix(data);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Could not load matrix data.");
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadMatrix();

    return () => {
      cancelled = true;
    };
  }, []);

  const matrixAsns = useMemo(
    () => sortAsns(Object.keys(matrix?.connectivity ?? {})),
    [matrix]
  );
  const sourceAsns = useMemo(
    () => matrixAsns.filter((asn) => !isReservedAsn(asn)),
    [matrixAsns]
  );
  const sourceAsnSet = useMemo(() => new Set(sourceAsns), [sourceAsns]);
  const hilbertAsns = useMemo(() => addRequiredHilbertAsns(matrixAsns), [matrixAsns]);
  const selectedAsn = normalizeAsn(asnInput);
  const hasSelectedAsn = selectedAsn.length > 0;
  const selectedRowExists = hasSelectedAsn && sourceAsnSet.has(selectedAsn);
  const leafDepth = 8;
  const leafPrefixes = useMemo(
    () => generateLeafPrefixes(leafDepth, hilbertAsns.length),
    [leafDepth, hilbertAsns.length]
  );
  const destinationByPrefix = useMemo(() => {
    const entries = leafPrefixes.map((prefix, index) => [prefix, hilbertAsns[index]] as const);
    return new Map(entries);
  }, [hilbertAsns, leafPrefixes]);

  const internalPrefixes = useMemo(
    () => generateInternalPrefixes(leafDepth),
    [leafDepth]
  );
  const aggregateByPrefix = useMemo(() => {
    const aggregates = new Map<string, AggregateReachability>();

    for (const prefix of internalPrefixes) {
      const destinations = getDestinationsForPrefix(prefix, hilbertAsns, leafDepth);
      aggregates.set(
        prefix,
        summarizeConnectivity(matrix, selectedRowExists, selectedAsn, destinations)
      );
    }

    return aggregates;
  }, [hilbertAsns, internalPrefixes, leafDepth, matrix, selectedAsn, selectedRowExists]);
  const leafPrefixSet = useMemo(() => new Set(leafPrefixes), [leafPrefixes]);

  const statusCounts = useMemo(
    () => summarizeRow(matrix, selectedAsn, sourceAsns),
    [matrix, selectedAsn, sourceAsns]
  );

  useEffect(() => {
    if (!initializedAsnInput.current && sourceAsns.length > 0) {
      initializedAsnInput.current = true;
      setAsnInput(sourceAsns[0]);
    }
  }, [sourceAsns]);

  const renderFunctions = useMemo<RenderFunction[]>(() => [
    (prefix, long, netmask, config) => {
      baseRender(prefix, long, netmask, config);

      const destinationAsn = destinationByPrefix.get(prefix);
      if (destinationAsn) {
        if (isReservedAsn(destinationAsn)) {
          config.style.backgroundColor = "#eeeeee";
          config.style.color = "#737373";
          config.innerContent = [renderReservedCell(destinationAsn)];
          config.properties = {
            ...config.properties,
            destinationAsn,
            reserved: true,
            statusLabel: "Reserved /8"
          };
          return;
        }

        const status = getStatus(matrix, selectedAsn, destinationAsn);
        const info = STATUS_INFO[status];
        config.style.backgroundColor = info.color;
        config.style.color = info.textColor;
        config.innerContent = [renderCell(destinationAsn, status)];
        config.properties = {
          ...config.properties,
          destinationAsn,
          status,
          statusLabel: info.label
        };
        return;
      }

      const aggregate = aggregateByPrefix.get(prefix);
      if (aggregate) {
        const colors = getAggregateColors(aggregate.connectivity);
        config.style.backgroundColor = colors.backgroundColor;
        config.style.color = colors.color;
        config.innerContent = [renderAggregateCell(prefix, aggregate)];
        config.properties = {
          ...config.properties,
          aggregatePrefix: prefix,
          aggregateReachability: aggregate
        };
        return;
      }

      if (leafPrefixSet.has(prefix)) {
        config.style.backgroundColor = "#eeeeee";
        config.style.color = "#737373";
        config.innerContent = [renderCell(undefined, "missing")];
        config.properties = {
          ...config.properties,
          status: "missing",
          statusLabel: STATUS_INFO.missing.label
        };
      }
    }
  ], [aggregateByPrefix, destinationByPrefix, leafPrefixSet, matrix, selectedAsn]);

  useEffect(() => {
    if (loading || error || hilbertAsns.length === 0 || internalPrefixes.length === 0) {
      return;
    }

    let splitFrame = 0;
    let resetFrame = 0;
    let followupResetFrame = 0;

    splitFrame = window.requestAnimationFrame(() => {
      clearAllPrefixes();
      setPrefixSplit(internalPrefixes, true);

      resetFrame = window.requestAnimationFrame(() => {
        hilbertStore.getState().resetZoom();

        followupResetFrame = window.requestAnimationFrame(() => {
          hilbertStore.getState().resetZoom();
        });
      });
    });

    return () => {
      window.cancelAnimationFrame(splitFrame);
      window.cancelAnimationFrame(resetFrame);
      window.cancelAnimationFrame(followupResetFrame);
    };
  }, [
    clearAllPrefixes,
    error,
    hilbertAsns.length,
    hilbertStore,
    internalPrefixes,
    loading,
    renderFunctions,
    setPrefixSplit
  ]);

  const hoverDestination = hoverPrefix.config.properties.destinationAsn as string | undefined;
  const hoverStatus = hoverPrefix.config.properties.status as ReachabilityStatus | undefined;
  const hoverReserved = hoverPrefix.config.properties.reserved as boolean | undefined;
  const hoverAggregatePrefix = hoverPrefix.config.properties.aggregatePrefix as string | undefined;
  const hoverAggregate = hoverPrefix.config.properties.aggregateReachability as
    | AggregateReachability
    | undefined;
  const hoverDestinationLabel = getHoverDestinationLabel(
    hoverDestination,
    hoverAggregate,
    hoverAggregatePrefix
  );
  const hoverStatusLabel = hoverReserved
    ? "Reserved /8"
    : hoverStatus
    ? STATUS_INFO[hoverStatus].label
    : hoverAggregate
      ? formatConnectivity(hoverAggregate.connectivity)
      : "-";
  const hoverDescription = hoverReserved
    ? `${hoverDestination ?? "This AS"}.0.0.0/8 is reserved and is not counted in aggregate connectivity.`
    : hoverStatus
    ? STATUS_INFO[hoverStatus].description
    : hoverAggregate
      ? hoverAggregate.total > 0
        ? `${hoverAggregate.reachable} of ${hoverAggregate.total} destination ASes are reachable from ${
          selectedAsn ? `AS${selectedAsn}` : "the selected AS"
        }.`
        : "This aggregate contains no non-reserved destination ASes."
      : "";

  return (
    <main className="hilbert-page">
      <section className="hilbert-header">
        <h1>reachability hilbert curve</h1>
        <div className="hilbert-controls">
          <label htmlFor="asn-input">AS number</label>
          <input
            id="asn-input"
            list="asn-options"
            inputMode="numeric"
            value={asnInput}
            onChange={(event) => setAsnInput(event.target.value)}
            placeholder={sourceAsns.length ? sourceAsns[0] : "AS"}
          />
          <datalist id="asn-options">
            {sourceAsns.map((asn) => (
              <option value={asn} key={asn} />
            ))}
          </datalist>
        </div>
      </section>

      {error && <p className="hilbert-message hilbert-error">{error}</p>}
      {!error && loading && <p className="hilbert-message">Loading matrix data...</p>}
      {!error && !loading && sourceAsns.length === 0 && (
        <p className="hilbert-message">No matrix data is available.</p>
      )}
      {!error && !loading && sourceAsns.length > 0 && hasSelectedAsn && !selectedRowExists && (
        <p className="hilbert-message hilbert-error">AS{selectedAsn} is not in the matrix.</p>
      )}

      <section className="hilbert-summary" aria-label="Selected AS reachability summary">
        {(["valid", "invalid", "failure", "missing"] as ReachabilityStatus[]).map((status) => (
          <div className="hilbert-stat" key={status}>
            <span
              className="hilbert-swatch"
              style={{ backgroundColor: STATUS_INFO[status].color }}
            />
            <span className="hilbert-stat-label">{STATUS_INFO[status].label}</span>
            <strong>{statusCounts[status]}</strong>
          </div>
        ))}
      </section>

      <section className="hilbert-workspace">
        <div className="hilbert-plot" tabIndex={0}>
          <div className="hilbert-frame">
            <InteractiveHilbert
              topPrefix={TOP_PREFIX}
              renderFunctions={renderFunctions}
              hilbertStore={hilbertStore}
              maxExpand={leafDepth}
            />
          </div>
        </div>
        <aside className="hilbert-details" aria-live="polite">
          <div>
            <span>Source</span>
            <strong>{selectedAsn ? `AS${selectedAsn}` : "-"}</strong>
          </div>
          <div>
            <span>Destination</span>
            <strong>{hoverDestinationLabel}</strong>
          </div>
          <div>
            <span>Status</span>
            <strong>{hoverStatusLabel}</strong>
          </div>
          <p>{hoverDescription}</p>
        </aside>
      </section>
    </main>
  );
}

function addRequiredHilbertAsns(matrixAsns: string[]): string[] {
  return sortAsns(Array.from(new Set(["0", ...matrixAsns])));
}

function isReservedAsn(asn: string | undefined): boolean {
  return asn !== undefined && RESERVED_ASNS.has(asn);
}

function getHoverDestinationLabel(
  destinationAsn: string | undefined,
  aggregate: AggregateReachability | undefined,
  aggregatePrefix: string | undefined
): string {
  if (destinationAsn) {
    return `AS${destinationAsn}`;
  }
  if (aggregatePrefix) {
    return aggregate?.total ? `${aggregatePrefix} (${aggregate.total} ASes)` : aggregatePrefix;
  }
  return "-";
}

function getDestinationsForPrefix(prefix: string, asns: string[], leafDepth: number): string[] {
  const { depth, index } = parsePrefix(prefix);
  if (depth > leafDepth) {
    return [];
  }

  const groupSize = 2 ** (leafDepth - depth);
  const start = index * groupSize;
  return asns.slice(start, start + groupSize);
}

function parsePrefix(prefix: string): { depth: number; index: number } {
  const [address, depthPart] = prefix.split("/");
  const depth = Number(depthPart);
  const blockSize = 2 ** (32 - depth);
  const addressValue = address
    .split(".")
    .map(Number)
    .reduce((value, octet) => value * 256 + octet, 0);

  return {
    depth,
    index: depth === 0 ? 0 : Math.floor(addressValue / blockSize)
  };
}

function summarizeConnectivity(
  matrix: MatrixRaw | null,
  selectedRowExists: boolean,
  sourceAsn: string,
  destinations: string[]
): AggregateReachability {
  const countedDestinations = destinations.filter((destinationAsn) => !isReservedAsn(destinationAsn));

  if (!matrix || !selectedRowExists || !sourceAsn || countedDestinations.length === 0) {
    return {
      connectivity: null,
      reachable: 0,
      total: countedDestinations.length
    };
  }

  const reachable = countedDestinations.filter((destinationAsn) => {
    const status = getStatus(matrix, sourceAsn, destinationAsn);
    return status === "valid" || status === "invalid";
  }).length;

  return {
    connectivity: reachable / countedDestinations.length,
    reachable,
    total: countedDestinations.length
  };
}

function getAggregateColors(connectivity: number | null): { backgroundColor: string; color: string } {
  if (connectivity === null) {
    return {
      backgroundColor: "#eeeeee",
      color: "#737373"
    };
  }

  const rgb = mixRgb([213, 96, 94], [86, 193, 87], connectivity);
  return {
    backgroundColor: formatRgb(rgb),
    color: getReadableTextColor(rgb)
  };
}

function mixRgb(
  start: [number, number, number],
  end: [number, number, number],
  ratio: number
): [number, number, number] {
  return start.map((channel, index) =>
    Math.round(channel + (end[index] - channel) * ratio)
  ) as [number, number, number];
}

function formatRgb(rgb: [number, number, number]): string {
  return `rgb(${rgb[0]} ${rgb[1]} ${rgb[2]})`;
}

function getReadableTextColor(rgb: [number, number, number]): string {
  const [red, green, blue] = rgb.map((channel) => {
    const normalized = channel / 255;
    return normalized <= 0.03928
      ? normalized / 12.92
      : ((normalized + 0.055) / 1.055) ** 2.4;
  });
  const luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
  return luminance > 0.36 ? "#111827" : "#ffffff";
}

function formatConnectivity(connectivity: number | null): string {
  if (connectivity === null) {
    return "No data";
  }
  return `${Math.round(connectivity * 100)}% average connectivity`;
}

function formatConnectivityShort(connectivity: number | null): string {
  if (connectivity === null) {
    return "No data";
  }
  return `${Math.round(connectivity * 100)}% avg`;
}

function renderAggregateCell(prefix: string, aggregate: AggregateReachability): ReactNode {
  if (aggregate.total === 0) {
    return (
      <span className="hilbert-cell hilbert-cell-aggregate" key={`aggregate-${prefix}`}>
        <span className="hilbert-cell-asn">{prefix}</span>
        <span className="hilbert-cell-prefix">No counted ASes</span>
      </span>
    );
  }

  return (
    <span className="hilbert-cell hilbert-cell-aggregate" key={`aggregate-${prefix}`}>
      <span className="hilbert-cell-asn">{prefix}</span>
      <span className="hilbert-cell-prefix">{formatConnectivityShort(aggregate.connectivity)}</span>
      <span className="hilbert-cell-prefix">
        {aggregate.reachable}/{aggregate.total} reachable
      </span>
    </span>
  );
}

function renderReservedCell(destinationAsn: string): ReactNode {
  return (
    <span className="hilbert-cell hilbert-cell-reserved" key={destinationAsn}>
      <span className="hilbert-cell-asn">AS{destinationAsn}</span>
      <span className="hilbert-cell-prefix">{destinationAsn}.0.0.0/8</span>
    </span>
  );
}

function renderCell(destinationAsn: string | undefined, status: ReachabilityStatus): ReactNode {
  if (!destinationAsn) {
    return <span className="hilbert-cell hilbert-cell-empty" key="empty" />;
  }

  return (
    <span className={`hilbert-cell hilbert-cell-${status}`} key={destinationAsn}>
      <span className="hilbert-cell-asn">AS{destinationAsn}</span>
      <span className="hilbert-cell-prefix">{destinationAsn}.0.0.0/8</span>
    </span>
  );
}

export default App;
