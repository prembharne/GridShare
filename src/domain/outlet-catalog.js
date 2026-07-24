// Static catalog of demo outlets. This is the single source of truth for the
// /outlets/nearby response AND for seeding the `outlets` (and their host
// `users`) rows into Postgres, so that session inserts satisfy their foreign
// keys when persistence is enabled.
//
// Each entry carries the extra fields the DB needs (hostId, providerDeviceId,
// location) that the client-facing /outlets/nearby payload doesn't expose.
export const OUTLET_CATALOG = [
  {
    id: "outlet_wipro_16a",
    name: "Wipro 16A Smart EV Charger",
    host_name: "Prem (Host)",
    hostId: "host_prem",
    providerDeviceId: "d72c4dd24f074a08fdwvz4",
    lat: 19.0760,
    lng: 72.8777,
    distance_km: 0.2,
    rate_per_kwh: 12.5,
    available: true,
    connector_type: "16A Socket",
    rating: 4.9,
    address: "Prem's Prosumer EV Station"
  }
];

// Shape used by the /outlets/nearby endpoint (the client-facing subset).
export function toNearbyPayload(outlet) {
  return {
    id: outlet.id,
    name: outlet.name,
    host_name: outlet.host_name,
    lat: outlet.lat,
    lng: outlet.lng,
    distance_km: outlet.distance_km,
    rate_per_kwh: outlet.rate_per_kwh,
    available: outlet.available,
    connector_type: outlet.connector_type,
    rating: outlet.rating
  };
}

export function findOutlet(id) {
  return OUTLET_CATALOG.find((o) => o.id === id);
}

// Seed the catalog's host users and outlets into persistent storage so that
// session inserts satisfy their foreign keys. No-op when the store doesn't
// support outlets (in-memory). Safe to call repeatedly (upserts).
export async function seedOutletCatalog({ store, users }) {
  if (typeof store.upsertOutlet !== "function") {
    return { seeded: 0 };
  }
  let seeded = 0;
  for (const outlet of OUTLET_CATALOG) {
    // The outlet's host must exist first (outlets.host_id -> users.id).
    await users.upsertUser({
      id: outlet.hostId,
      role: "host",
      displayName: outlet.host_name
    });
    await store.upsertOutlet({
      id: outlet.id,
      hostId: outlet.hostId,
      displayName: outlet.name,
      providerDeviceId: outlet.providerDeviceId,
      address: outlet.address,
      lat: outlet.lat,
      lng: outlet.lng,
      status: outlet.available ? "available" : "offline"
    });
    seeded += 1;
  }
  return { seeded };
}
