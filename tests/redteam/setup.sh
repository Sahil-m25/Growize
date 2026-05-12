#!/usr/bin/env bash
# Source this script to set environment variables for red-team tests.
# Variables set:
#   SUPABASE_URL - Supabase project endpoint
#   ANON_KEY - Supabase anonymous API key
#   REAL_INVESTOR_JWT - Valid JWT from signed-in test investor
#   REAL_INVESTOR_ID - Auth UID of test investor
#   VICTIM_INVESTOR_ID - Dummy ID for testing access controls

# SUPABASE_URL is pre-filled. Get ANON_KEY and REAL_INVESTOR_JWT by:
# 1. Sign in to the Flutter app as a test investor account.
# 2. In Supabase Studio → Project Settings → API, copy the anon key (anonKey).
# 3. In the Flutter app, open DevTools or add a debug print to main.dart:
#    print('JWT: ${client.auth.currentSession?.accessToken}');
#    Also print auth.uid() to get REAL_INVESTOR_ID.
# 4. Paste both values below (replace <paste ...>).

export SUPABASE_URL="https://oynfhdqizebvgmaoiuax.supabase.co"
export ANON_KEY="<paste anon key from Supabase Studio → API>"
export REAL_INVESTOR_JWT="<paste JWT from signed-in Flutter app session>"
export REAL_INVESTOR_ID="<paste auth.uid() from signed-in session>"
export VICTIM_INVESTOR_ID="00000000-0000-0000-0000-000000000999"
