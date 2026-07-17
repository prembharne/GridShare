#!/usr/bin/env node

// Migration runner for database schema
// Usage: node scripts/migrate.js

import { PrismaClient } from "@prisma/client";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const prisma = new PrismaClient();

async function migrate() {
  console.log("Running migrations...");

  const migrationPath = join(__dirname, "..", "migrations", "001_initial_schema.sql");
  const sql = readFileSync(migrationPath, "utf-8");

  const statements = sql.split(";").map(s => s.trim()).filter(s => s.length > 0);

  for (const statement of statements) {
    try {
      await prisma.$executeRawUnsafe(statement + ";");
      console.log("✓ Executed:", statement.slice(0, 60) + "...");
    } catch (error) {
      if (error.message.includes("already exists") || error.message.includes("duplicate")) {
        console.log("⊘ Skipped (exists):", statement.slice(0, 60) + "...");
      } else {
        console.error("✗ Failed:", statement.slice(0, 60) + "...");
        console.error(error.message);
        throw error;
      }
    }
  }

  console.log("Migrations complete!");
  await prisma.$disconnect();
}

migrate().catch((error) => {
  console.error("Migration failed:", error);
  process.exit(1);
});