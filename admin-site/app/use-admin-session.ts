"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { createClient, type Session } from "@supabase/supabase-js";
import type { Row, RuntimeConfig } from "./admin-types";

export function useAdminSession() {
  const [config, setConfig] = useState<RuntimeConfig | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [configurationError, setConfigurationError] = useState("");
  const supabase = useMemo(
    () => config ? createClient(config.supabaseUrl, config.supabaseAnonKey, { auth: { detectSessionInUrl: true, persistSession: true } }) : null,
    [config],
  );

  useEffect(() => {
    fetch("/api/config")
      .then(async (response) => {
        const value = await response.json();
        if (!response.ok) throw new Error(value.error ?? "Dashboard configuration is unavailable.");
        setConfig(value);
      })
      .catch(() => setConfigurationError("The dashboard is not configured yet."));
  }, []);

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, [supabase]);

  const api = useCallback(async (body: Row) => {
    if (!session || !config) throw new Error("Sign in required.");
    const response = await fetch(config.adminApiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}`, apikey: config.supabaseAnonKey },
      body: JSON.stringify(body),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(result.error ?? "The request could not be completed.");
    return result;
  }, [config, session]);

  return { api, config, configurationError, session, supabase };
}
