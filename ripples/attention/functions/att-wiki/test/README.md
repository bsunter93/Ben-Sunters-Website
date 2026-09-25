Mock suite for att-wiki (fake fetch + in-memory RPC stub; no network, no database).

    cd <tmp>; sed 's#^import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";#import { createClient } from "./stub.mts"; type SupabaseClient = any;#' ../../_shared/att.ts > att.mts
    sed 's#from "./att.ts";#from "./att.mts";#' ../index.ts > index.mts
    cp test.mts stub.mts <tmp>/ && node --experimental-transform-types test.mts     # 44/44 on 2026-09-25 (w2)
