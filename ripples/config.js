// Knock-On v5 frontend constants (SPEC §10.2). The publishable key is public by design:
// it can only call the anon RPCs, which are SECURITY DEFINER and validate their input.
export const SB_URL = 'https://kffkasnzqcddpystszch.supabase.co';
export const SB_KEY = 'sb_publishable_3UtNDc2vPbCIcG1t5K4YEQ_KUyTKucv';
export const STORAGE = SB_URL + '/storage/v1/object/public/ripples/v1';
export const OG = SB_URL + '/functions/v1/ripples-og';
export const EPOCH = '2026-09-25';
// Stripe Payment Links (owner pastes them). null: support hidden; report/partner fall back to a mailto.
// D-1: support = pay what you want from $2, unlocks nothing (replaces Founding Radar $5/mo).
export const STRIPE = { support: null, report149: null, partner500: null };
// RSS feed URL once one is published; the reminder row shows it only when set.
export const RSS = null;
export const CONTACT = 'sunterbb@gmail.com';
export const SITE = 'bensunter.com/ripples';
export const METHOD = '5.0';
