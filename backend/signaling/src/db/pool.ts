import fs from "node:fs";
import path from "node:path";
import pg from "pg";
import { config } from "../config.js";

const { Pool } = pg;

export const pool = new Pool({
  connectionString: config.databaseUrl,
  max: 10,
  ssl:
    process.env.DATABASE_SSL === "true" || process.env.DATABASE_SSL === "require"
      ? { rejectUnauthorized: false }
      : undefined,
});

export async function migrate(): Promise<void> {
  const here = __dirname;
  const sql = fs.readFileSync(path.join(here, "schema.sql"), "utf8");
  let last: unknown;
  for (let i = 0; i < 20; i += 1) {
    try {
      await pool.query(sql);
      console.log("[db] schema ready");
      return;
    } catch (err) {
      last = err;
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  throw last;
}

export async function query<T extends pg.QueryResultRow>(
  text: string,
  params?: unknown[],
): Promise<pg.QueryResult<T>> {
  return pool.query<T>(text, params);
}
