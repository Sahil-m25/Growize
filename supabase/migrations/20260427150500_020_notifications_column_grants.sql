-- Migration 020: Restore UPDATE (read_at) column grant on notifications for authenticated

GRANT UPDATE (read_at) ON public.notifications TO authenticated;
