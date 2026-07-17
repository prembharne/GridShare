#!/usr/bin/env node

// Seed script for demo data
// Usage: node scripts/seed.js

import { PrismaClient } from "@prisma/client";
import crypto from "node:crypto";

const prisma = new PrismaClient();

async function seed() {
  console.log("Seeding demo data...");

  // Create demo users
  const rider = await prisma.user.upsert({
    where: { id: "rider_demo" },
    update: {},
    create: {
      id: "rider_demo",
      role: "rider",
      phoneE164: "+919876543210",
      displayName: "Demo Rider"
    }
  });

  const host = await prisma.user.upsert({
    where: { id: "host_demo" },
    update: {},
    create: {
      id: "host_demo",
      role: "host",
      phoneE164: "+919876543211",
      displayName: "Demo Host"
    }
  });

  // Create demo outlet
  const outlet = await prisma.outlet.upsert({
    where: { id: "outlet_demo" },
    update: {},
    create: {
      id: "outlet_demo",
      hostId: host.id,
      displayName: "GridShare Demo Station",
      deviceProvider: "tuya",
      providerDeviceId: "tuya_demo_device_001",
      location: "POINT(77.5946 12.9716)", // Bangalore coordinates
      address: "123 Demo Street, Bangalore",
      maxCurrentAmp: 16,
      status: "available"
    }
  });

  console.log("Demo users and outlet created:");
  console.log(`  Rider: ${rider.id}`);
  console.log(`  Host: ${host.id}`);
  console.log(`  Outlet: ${outlet.id} (${outlet.providerDeviceId})`);

  await prisma.$disconnect();
}

seed().catch((error) => {
  console.error("Seed failed:", error);
  process.exit(1);
});