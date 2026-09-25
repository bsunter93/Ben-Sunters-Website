// Knock-On v5 frontend constants (SPEC §10.2). The publishable key is public by design:
// it can only call the anon RPCs, which are SECURITY DEFINER and validate their input.
export const SB_URL = 'https://kffkasnzqcddpystszch.supabase.co';
export const SB_KEY = 'sb_publishable_3UtNDc2vPbCIcG1t5K4YEQ_KUyTKucv';
export const STORAGE = SB_URL + '/storage/v1/object/public/ripples/v1';
export const OG = SB_URL + '/functions/v1/ripples-og';
export const EPOCH = '2026-09-25';
// Stripe Payment Links. null = not open yet: buttons record intent or fall back to a mailto.
export const STRIPE = { radar5: null, report149: null, partner500: null };
export const CONTACT = 'sunterbb@gmail.com';
export const SITE = 'bensunter.com/ripples';
export const METHOD = '5.0';
