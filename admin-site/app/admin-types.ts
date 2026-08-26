/* eslint-disable @typescript-eslint/no-explicit-any */
export type Tab = "queue" | "foods" | "ingredients";
export type Row = Record<string, any>;
export type RuntimeConfig = {
  supabaseUrl: string;
  supabaseAnonKey: string;
  adminApiUrl: string;
};
export type QueueFilter = "active" | "pending_review" | "needs_review" | "processing" | "draft" | "accepted" | "rejected";

export const queueFilters: { value: QueueFilter; label: string }[] = [
  { value: "active", label: "All active" },
  { value: "pending_review", label: "Ready for review" },
  { value: "needs_review", label: "Needs photos" },
  { value: "processing", label: "Processing" },
  { value: "draft", label: "Drafts" },
  { value: "accepted", label: "Approved" },
  { value: "rejected", label: "Rejected" },
];
