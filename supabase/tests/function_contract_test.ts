import { assert, assertEquals } from "jsr:@std/assert@1";

const fixtures = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../../SharedContracts/function-request-fixtures.json",
      import.meta.url,
    ),
  ),
) as Record<string, Record<string, unknown>>;

Deno.test("every app function contract names a deployed function and supported action", async () => {
  for (const [functionName, payload] of Object.entries(fixtures)) {
    const source = await Deno.readTextFile(
      new URL(`../functions/${functionName}/index.ts`, import.meta.url),
    );
    if (typeof payload.action === "string") {
      assert(
        source.includes(`"${payload.action}"`) ||
          source.includes(`'${payload.action}'`),
        `${functionName} does not declare action ${payload.action}`,
      );
    }
  }
  assertEquals(Object.keys(fixtures).length, 11);
});

Deno.test("write-hole migration revokes direct authenticated mutations", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../migrations/202608280001_close_authenticated_write_paths.sql",
      import.meta.url,
    ),
  );
  assert(
    migration.toLowerCase().includes(
      "revoke insert, update, delete on public.food_entries from authenticated",
    ),
  );
  assert(
    migration.toLowerCase().includes(
      "revoke update (acknowledged_at) on public.plan_adjustments from authenticated",
    ),
  );
});
