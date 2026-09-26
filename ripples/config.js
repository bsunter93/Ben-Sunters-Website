// Ripple Map v6 constants. The publishable key is public: it only reaches the anon RPCs (rm_* reads, rm_event, ripples_join).
export const SB_URL = 'https://kffkasnzqcddpystszch.supabase.co';
export const SB_KEY = 'sb_publishable_3UtNDc2vPbCIcG1t5K4YEQ_KUyTKucv';
export const STORAGE = SB_URL + '/storage/v1/object/public/ripples/v2/';
export const OG = SB_URL + '/functions/v1/ripples-og';
// Stripe Payment Links (owner pastes). null: the Support block stays hidden (D-1: pay what you want, from $2).
export const STRIPE = { support: null, report149: null, partner500: null };
export const CONTACT = 'sunterbb@gmail.com';
export const SITE = 'bensunter.com/ripples';
export const METHOD = '6.0';
