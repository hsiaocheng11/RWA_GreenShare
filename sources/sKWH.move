// FILE: sources/sKWH.move
/// sKWH: Sustainable Kilowatt-Hour RWA Token
/// Represents real-world energy assets in tokenized form
module greenshare::sKWH {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};

    // ==================== Errors ====================
    
    const EInsufficientQuota: u64 = 1;
    const EProofAlreadyUsed: u64 = 2;
    const EInvalidAmount: u64 = 3;
    const EInvalidProof: u64 = 4;
    const EUnauthorized: u64 = 5;
    const EQuotaNotFound: u64 = 6;

    // ==================== Structs ====================

    /// One-Time-Witness for sKWH token
    public struct SKWH has drop {}

    /// Quota Ledger: tracks available minting quota per time window
    public struct QuotaLedger has key {
        id: UID,
        /// window_id -> available_quota (in micro-sKWH, 6 decimals)
        quotas: Table<String, u64>,
        /// Used proofs to prevent double-spending
        used_proofs: Table<String, bool>,
        /// Admin capability
        admin_cap: address,
    }

    /// Administrative capability for quota management
    public struct AdminCap has key, store {
        id: UID,
    }

    // ==================== Events ====================

    public struct Minted has copy, drop {
        proof_hash: String,
        window_id: String,
        amount: u64,
        recipient: address,
        timestamp: u64,
    }

    public struct Burned has copy, drop {
        amount: u64,
        burner: address,
        timestamp: u64,
    }

    public struct ProofBound has copy, drop {
        proof_hash: String,
        window_id: String,
        timestamp: u64,
    }

    public struct QuotaSet has copy, drop {
        window_id: String,
        quota_amount: u64,
        timestamp: u64,
    }

    // ==================== Initialization ====================

    /// Initialize sKWH token and create quota ledger
    fun init(witness: SKWH, ctx: &mut TxContext) {
        // Create sKWH coin
        let (treasury_cap, metadata) = coin::create_currency<SKWH>(
            witness,
            6, // 6 decimals for micro-sKWH precision
            b"sKWH",
            b"Sustainable Kilowatt-Hour",
            b"Tokenized renewable energy certificates backed by verified solar generation data",
            option::none(),
            ctx
        );

        // Transfer treasury cap to deployer for initial management
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::public_freeze_object(metadata);

        // Create quota ledger
        let quota_ledger = QuotaLedger {
            id: object::new(ctx),
            quotas: table::new(ctx),
            used_proofs: table::new(ctx),
            admin_cap: tx_context::sender(ctx),
        };

        // Create admin capability
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };

        transfer::share_object(quota_ledger);
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
    }

    // ==================== Core Functions ====================

    /// Mint sKWH tokens from verified proof
    public entry fun mint_from_proof(
        treasury_cap: &mut TreasuryCap<SKWH>,
        quota_ledger: &mut QuotaLedger,
        proof_hash: String,
        window_id: String,
        amount: u64, // Amount in micro-sKWH (6 decimals)
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate inputs
        assert!(amount > 0, EInvalidAmount);
        assert!(string::length(&proof_hash) > 0, EInvalidProof);

        // Check if proof already used
        assert!(
            !table::contains(&quota_ledger.used_proofs, proof_hash),
            EProofAlreadyUsed
        );

        // Check quota availability
        assert!(
            table::contains(&quota_ledger.quotas, window_id),
            EQuotaNotFound
        );

        let available_quota = *table::borrow(&quota_ledger.quotas, window_id);
        assert!(amount <= available_quota, EInsufficientQuota);

        // Update quota and mark proof as used
        let remaining_quota = available_quota - amount;
        *table::borrow_mut(&mut quota_ledger.quotas, window_id) = remaining_quota;
        table::add(&mut quota_ledger.used_proofs, proof_hash, true);

        // Mint tokens
        let coin = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(coin, recipient);

        // Emit events
        event::emit(Minted {
            proof_hash,
            window_id,
            amount,
            recipient,
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(ProofBound {
            proof_hash,
            window_id,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Burn sKWH tokens
    public entry fun burn(
        treasury_cap: &mut TreasuryCap<SKWH>,
        coin: Coin<SKWH>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&coin);
        coin::burn(treasury_cap, coin);

        event::emit(Burned {
            amount,
            burner: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // ==================== Admin Functions ====================

    /// Set quota for a specific time window (admin only)
    public entry fun set_quota(
        _admin_cap: &AdminCap,
        quota_ledger: &mut QuotaLedger,
        window_id: String,
        quota_amount: u64,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        if (table::contains(&quota_ledger.quotas, window_id)) {
            *table::borrow_mut(&mut quota_ledger.quotas, window_id) = quota_amount;
        } else {
            table::add(&mut quota_ledger.quotas, window_id, quota_amount);
        };

        event::emit(QuotaSet {
            window_id,
            quota_amount,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Batch set quotas for multiple windows
    public entry fun batch_set_quotas(
        admin_cap: &AdminCap,
        quota_ledger: &mut QuotaLedger,
        window_ids: vector<String>,
        quota_amounts: vector<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let len = std::vector::length(&window_ids);
        assert!(len == std::vector::length(&quota_amounts), EInvalidAmount);

        let i = 0;
        while (i < len) {
            let window_id = *std::vector::borrow(&window_ids, i);
            let quota_amount = *std::vector::borrow(&quota_amounts, i);
            
            set_quota(admin_cap, quota_ledger, window_id, quota_amount, clock, ctx);
            i = i + 1;
        };
    }

    /// Transfer admin capability
    public entry fun transfer_admin(
        admin_cap: AdminCap,
        new_admin: address,
        quota_ledger: &mut QuotaLedger,
        _ctx: &mut TxContext
    ) {
        quota_ledger.admin_cap = new_admin;
        transfer::public_transfer(admin_cap, new_admin);
    }

    // ==================== Query Functions ====================

    /// Get available quota for a window
    public fun get_quota(quota_ledger: &QuotaLedger, window_id: String): u64 {
        if (table::contains(&quota_ledger.quotas, window_id)) {
            *table::borrow(&quota_ledger.quotas, window_id)
        } else {
            0
        }
    }

    /// Check if proof has been used
    public fun is_proof_used(quota_ledger: &QuotaLedger, proof_hash: String): bool {
        table::contains(&quota_ledger.used_proofs, proof_hash)
    }

    /// Get admin address
    public fun get_admin(quota_ledger: &QuotaLedger): address {
        quota_ledger.admin_cap
    }

    // ==================== Utility Functions ====================

    /// Convert sKWH to micro-sKWH (multiply by 10^6)
    public fun to_micro_skwh(skwh_amount: u64): u64 {
        skwh_amount * 1_000_000
    }

    /// Convert micro-sKWH to sKWH (divide by 10^6)
    public fun from_micro_skwh(micro_skwh_amount: u64): u64 {
        micro_skwh_amount / 1_000_000
    }

    // ==================== Testing Functions ====================

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(SKWH {}, ctx);
    }

    #[test_only]
    public fun create_test_quota_ledger(ctx: &mut TxContext): QuotaLedger {
        QuotaLedger {
            id: object::new(ctx),
            quotas: table::new(ctx),
            used_proofs: table::new(ctx),
            admin_cap: tx_context::sender(ctx),
        }
    }
}