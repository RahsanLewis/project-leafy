alter table public.account_legal_acceptances
  drop constraint if exists account_legal_acceptances_document_key_check;

alter table public.account_legal_acceptances
  add constraint account_legal_acceptances_document_key_check
  check (document_key in ('terms_of_use', 'privacy_policy', 'core_data_use'));
