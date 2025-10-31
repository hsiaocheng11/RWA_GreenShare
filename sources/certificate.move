// FILE: sources/certificate.move
/// Energy Certificate NFT with Kiosk support
/// Monthly certificates containing verified energy production metadata
module greenshare::certificate {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use std::string::{Self, String};
    use sui::clock::{Self, Clock};
    use sui::display;
    use sui::package;
    use std::option;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap};

    // ==================== Errors ====================
    
    const EInvalidMetadata: u64 = 1;
    const EUnauthorized: u64 = 2;
    const ECertificateExists: u64 = 3;
    const EInvalidTimestamp: u64 = 4;

    // ==================== Structs ====================

    /// One-Time-Witness for Certificate
    public struct CERTIFICATE has drop {}

    /// Energy Certificate NFT
    public struct Certificate has key, store {
        id: UID,
        /// Merkle root hash from ROFL proof
        proof_hash: String,
        /// Time window identifier (e.g., "2024-01-01T00:00:00Z")
        window_start: String,
        window_end: String,
        /// Aggregated energy production in micro-kWh
        total_kwh: u64,
        /// Number of contributing smart meters
        meter_count: u64,
        /// Household/community identifier hash
        household_hash: String,
        /// Walrus/Seal storage blob ID
        seal_blob_id: String,
        /// Certificate metadata
        issued_at: u64,
        issuer: address,
        /// Certificate serial number for uniqueness
        serial_number: String,
    }

    /// Certificate Publisher capability
    public struct PublisherCap has key, store {
        id: UID,
    }

    /// Certificate Registry to prevent duplicates
    public struct CertificateRegistry has key {
        id: UID,
        /// proof_hash -> certificate_id mapping
        issued_certificates: sui::table::Table<String, bool>,
        /// Total certificates issued
        total_issued: u64,
        /// Publisher address
        publisher: address,
    }

    // ==================== Events ====================

    public struct CertificateIssued has copy, drop {
        certificate_id: address,
        proof_hash: String,
        window_start: String,
        window_end: String,
        total_kwh: u64,
        household_hash: String,
        seal_blob_id: String,
        serial_number: String,
        timestamp: u64,
    }

    public struct CertificateTransferred has copy, drop {
        certificate_id: address,
        from: address,
        to: address,
        timestamp: u64,
    }

    public struct CertificatePlacedInKiosk has copy, drop {
        certificate_id: address,
        kiosk_id: address,
        timestamp: u64,
    }

    // ==================== Initialization ====================

    fun init(otw: CERTIFICATE, ctx: &mut TxContext) {
        let keys = std::vector::empty<String>();
        let values = std::vector::empty<String>();

        // Add display metadata
        std::vector::push_back(&mut keys, std::string::utf8(b"name"));
        std::vector::push_back(&mut values, std::string::utf8(b"GreenShare Energy Certificate #{serial_number}"));

        std::vector::push_back(&mut keys, std::string::utf8(b"description"));
        std::vector::push_back(&mut values, std::string::utf8(b"Verified renewable energy production certificate backed by cryptographic proofs"));

        std::vector::push_back(&mut keys, std::string::utf8(b"image_url"));
        std::vector::push_back(&mut values, std::string::utf8(b"https://greenshare.example.com/certificates/{seal_blob_id}/image"));

        std::vector::push_back(&mut keys, std::string::utf8(b"external_url"));
        std::vector::push_back(&mut values, std::string::utf8(b"https://greenshare.example.com/certificates/{proof_hash}"));

        std::vector::push_back(&mut keys, std::string::utf8(b"total_kwh"));
        std::vector::push_back(&mut values, std::string::utf8(b"{total_kwh}"));

        std::vector::push_back(&mut keys, std::string::utf8(b"window_period"));
        std::vector::push_back(&mut values, std::string::utf8(b"{window_start} to {window_end}"));

        std::vector::push_back(&mut keys, std::string::utf8(b"proof_hash"));
        std::vector::push_back(&mut values, std::string::utf8(b"{proof_hash}"));

        std::vector::push_back(&mut keys, std::string::utf8(b"seal_blob_id"));
        std::vector::push_back(&mut values, std::string::utf8(b"{seal_blob_id}"));

        // Create and transfer display object
        let publisher = package::claim(otw, ctx);
        let display = display::new_with_fields<Certificate>(
            &publisher, keys, values, ctx
        );
        display::update_version(&mut display);

        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));

        // Create certificate registry
        let registry = CertificateRegistry {
            id: object::new(ctx),
            issued_certificates: sui::table::new(ctx),
            total_issued: 0,
            publisher: tx_context::sender(ctx),
        };

        // Create publisher capability
        let publisher_cap = PublisherCap {
            id: object::new(ctx),
        };

        transfer::share_object(registry);
        transfer::public_transfer(publisher_cap, tx_context::sender(ctx));

        // Create default transfer policy for Kiosk integration
        let (transfer_policy, transfer_policy_cap) = transfer_policy::new<Certificate>(&publisher, ctx);
        transfer::public_share_object(transfer_policy);
        transfer::public_transfer(transfer_policy_cap, tx_context::sender(ctx));
    }

    // ==================== Core Functions ====================

    /// Issue a new energy certificate
    public entry fun issue_certificate(
        _publisher_cap: &PublisherCap,
        registry: &mut CertificateRegistry,
        proof_hash: String,
        window_start: String,
        window_end: String,
        total_kwh: u64,
        meter_count: u64,
        household_hash: String,
        seal_blob_id: String,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate inputs
        assert!(std::string::length(&proof_hash) > 0, EInvalidMetadata);
        assert!(std::string::length(&seal_blob_id) > 0, EInvalidMetadata);
        assert!(total_kwh > 0, EInvalidMetadata);

        // Check if certificate already exists for this proof
        assert!(
            !sui::table::contains(&registry.issued_certificates, proof_hash),
            ECertificateExists
        );

        // Generate serial number
        let serial_number = generate_serial_number(registry.total_issued + 1);

        // Create certificate
        let certificate = Certificate {
            id: object::new(ctx),
            proof_hash,
            window_start,
            window_end,
            total_kwh,
            meter_count,
            household_hash,
            seal_blob_id,
            issued_at: clock::timestamp_ms(clock),
            issuer: tx_context::sender(ctx),
            serial_number,
        };

        let certificate_id = object::id_address(&certificate);

        // Update registry
        sui::table::add(&mut registry.issued_certificates, proof_hash, true);
        registry.total_issued = registry.total_issued + 1;

        // Emit event
        event::emit(CertificateIssued {
            certificate_id,
            proof_hash,
            window_start,
            window_end,
            total_kwh,
            household_hash,
            seal_blob_id,
            serial_number,
            timestamp: clock::timestamp_ms(clock),
        });

        // Transfer to recipient
        transfer::public_transfer(certificate, recipient);
    }

    /// Place certificate in Kiosk for trading
    public entry fun place_in_kiosk(
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        certificate: Certificate,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        let certificate_id = object::id_address(&certificate);
        kiosk::place(kiosk, kiosk_cap, certificate);

        event::emit(CertificatePlacedInKiosk {
            certificate_id,
            kiosk_id: object::id_address(kiosk),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Take certificate from Kiosk
    public entry fun take_from_kiosk(
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        certificate_id: object::ID,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let certificate: Certificate = kiosk::take(kiosk, kiosk_cap, certificate_id);
        
        event::emit(CertificateTransferred {
            certificate_id: object::id_address(&certificate),
            from: object::id_address(kiosk),
            to: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });

        transfer::public_transfer(certificate, tx_context::sender(ctx));
    }

    /// List certificate for sale in Kiosk
    public entry fun list_for_sale(
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        certificate_id: object::ID,
        price: u64,
        _ctx: &mut TxContext
    ) {
        kiosk::list<Certificate>(kiosk, kiosk_cap, certificate_id, price);
    }

    /// Purchase certificate from Kiosk
    public entry fun purchase_from_kiosk(
        kiosk: &mut Kiosk,
        certificate_id: object::ID,
        payment: sui::coin::Coin<sui::sui::SUI>,
        transfer_policy: &TransferPolicy<Certificate>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let (certificate, transfer_request) = kiosk::purchase<Certificate>(
            kiosk, certificate_id, payment
        );

        let certificate_addr = object::id_address(&certificate);
        let buyer = tx_context::sender(ctx);

        // Complete transfer policy requirements
        transfer_policy::confirm_request(transfer_policy, transfer_request);

        event::emit(CertificateTransferred {
            certificate_id: certificate_addr,
            from: object::id_address(kiosk),
            to: buyer,
            timestamp: clock::timestamp_ms(clock),
        });

        transfer::public_transfer(certificate, buyer);
    }

    // ==================== Query Functions ====================

    /// Get certificate metadata
    public fun get_certificate_info(certificate: &Certificate): (
        String, String, String, u64, u64, String, String, u64, address, String
    ) {
        (
            certificate.proof_hash,
            certificate.window_start,
            certificate.window_end,
            certificate.total_kwh,
            certificate.meter_count,
            certificate.household_hash,
            certificate.seal_blob_id,
            certificate.issued_at,
            certificate.issuer,
            certificate.serial_number
        )
    }

    /// Check if certificate exists for proof
    public fun is_certificate_issued(registry: &CertificateRegistry, proof_hash: String): bool {
        sui::table::contains(&registry.issued_certificates, proof_hash)
    }

    /// Get total certificates issued
    public fun get_total_issued(registry: &CertificateRegistry): u64 {
        registry.total_issued
    }

    /// Get certificate proof hash
    public fun get_proof_hash(certificate: &Certificate): String {
        certificate.proof_hash
    }

    /// Get certificate energy amount
    public fun get_total_kwh(certificate: &Certificate): u64 {
        certificate.total_kwh
    }

    /// Get certificate seal blob ID
    public fun get_seal_blob_id(certificate: &Certificate): String {
        certificate.seal_blob_id
    }

    // ==================== Admin Functions ====================

    /// Transfer publisher capability
    public entry fun transfer_publisher_cap(
        publisher_cap: PublisherCap,
        new_publisher: address,
        registry: &mut CertificateRegistry,
        _ctx: &mut TxContext
    ) {
        registry.publisher = new_publisher;
        transfer::public_transfer(publisher_cap, new_publisher);
    }

    // ==================== Utility Functions ====================

    /// Generate sequential serial number
    fun generate_serial_number(number: u64): String {
        let prefix = std::string::utf8(b"GS-CERT-");
        let number_str = u64_to_string(number);
        std::string::append(&mut prefix, number_str);
        prefix
    }

    /// Convert u64 to string (simplified implementation)
    fun u64_to_string(value: u64): String {
        if (value == 0) {
            return std::string::utf8(b"0")
        };

        let digits = std::vector::empty<u8>();
        let temp = value;
        
        while (temp > 0) {
            let digit = ((temp % 10) as u8) + 48; // ASCII '0' = 48
            std::vector::push_back(&mut digits, digit);
            temp = temp / 10;
        };

        std::vector::reverse(&mut digits);
        std::string::utf8(digits)
    }

    // ==================== Testing Functions ====================

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(CERTIFICATE {}, ctx);
    }

    #[test_only]
    public fun create_test_certificate(
        proof_hash: String,
        total_kwh: u64,
        ctx: &mut TxContext
    ): Certificate {
        Certificate {
            id: object::new(ctx),
            proof_hash,
            window_start: std::string::utf8(b"2024-01-01T00:00:00Z"),
            window_end: std::string::utf8(b"2024-01-01T23:59:59Z"),
            total_kwh,
            meter_count: 1,
            household_hash: std::string::utf8(b"test_household"),
            seal_blob_id: std::string::utf8(b"test_blob_id"),
            issued_at: 1640995200000,
            issuer: tx_context::sender(ctx),
            serial_number: std::string::utf8(b"GS-CERT-1"),
        }
    }
}