// Knock-On v5 constants (SPEC §10.2). The publishable key is public: it only reaches the anon RPCs.
export const SB_URL = 'https://kffkasnzqcddpystszch.supabase.co';
export const SB_KEY = 'sb_publishable_3UtNDc2vPbCIcG1t5K4YEQ_KUyTKucv';
export const STORAGE = SB_URL + '/storage/v1/object/public/ripples/v1';
export const OG = SB_URL + '/functions/v1/ripples-og';
export const EPOCH = '2026-09-25';
// Stripe Payment Links (owner pastes). null: support hidden, others use mailto. D-1: support = PWYW from $2.
export const STRIPE = { support: null, report149: null, partner500: null };
// RSS feed URL; the link shows only when set.
export const RSS = null;
export const CONTACT = 'sunterbb@gmail.com';
export const SITE = 'bensunter.com/ripples';
export const METHOD = '5.0';
