// FILE: tests/certificate_tests.move
#[test_only]
module greenshare::certificate_tests {
    use greenshare::certificate::{Self, Certificate, PublisherCap, CertificateRegistry};
    use sui::test_scenario::{Self, Scenario};
    use sui::clock;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::transfer_policy::{Self, TransferPolicy};
    use sui::coin::{Self};
    use sui::sui::SUI;
    use std::string;

    // Test addresses
    const PUBLISHER: address = @0xPUBL;
    const USER1: address = @0x1111;
    const USER2: address = @0x2222;

    #[test]
    fun test_certificate_issuance() {
        let mut scenario = test_scenario::begin(PUBLISHER);
        let ctx = test_scenario::ctx(&mut scenario);

        // Initialize certificate module
        certificate::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, PUBLISHER);

        // Get objects created during init
        let publisher_cap = test_scenario::take_from_sender<PublisherCap>(&scenario);
        let mut registry = test_scenario::take_shared<CertificateRegistry>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Issue a certificate
        let proof_hash = string::utf8(b"test_proof_hash_12345");
        let window_start = string::utf8(b"2024-01-01T00:00:00Z");
        let window_end = string::utf8(b"2024-01-01T23:59:59Z");
        let total_kwh = 1500; // 1.5 kWh in micro-kWh
        let meter_count = 5;
        let household_hash = string::utf8(b"household_abc123");
        let seal_blob_id = string::utf8(b"walrus_blob_xyz789");

        certificate::issue_certificate(
            &publisher_cap,
            &mut registry,
            proof_hash,
            window_start,
            window_end,
            total_kwh,
            meter_count,
            household_hash,
            seal_blob_id,
            USER1,
            &clock,
            ctx
        );

        // Verify certificate was issued
        assert!(certificate::is_certificate_issued(&registry, proof_hash), 0);
        assert!(certificate::get_total_issued(&registry) == 1, 1);

        test_scenario::next_tx(&mut scenario, USER1);

        // Verify USER1 received the certificate
        let certificate = test_scenario::take_from_sender<Certificate>(&scenario);
        
        // Check certificate metadata
        let (cert_proof_hash, cert_window_start, cert_window_end, cert_total_kwh, 
             cert_meter_count, cert_household_hash, cert_seal_blob_id, 
             _issued_at, _issuer, _serial_number) = certificate::get_certificate_info(&certificate);

        assert!(cert_proof_hash == proof_hash, 2);
        assert!(cert_window_start == window_start, 3);
        assert!(cert_window_end == window_end, 4);
        assert!(cert_total_kwh == total_kwh, 5);
        assert!(cert_meter_count == meter_count, 6);
        assert!(cert_household_hash == household_hash, 7);
        assert!(cert_seal_blob_id == seal_blob_id, 8);

        // Clean up
        test_scenario::return_to_sender(&scenario, certificate);
        test_scenario::return_to_sender(&scenario, publisher_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = certificate::ECertificateExists)]
    fun test_duplicate_certificate_prevention() {
        let mut scenario = test_scenario::begin(PUBLISHER);
        let ctx = test_scenario::ctx(&mut scenario);

        certificate::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, PUBLISHER);

        let publisher_cap = test_scenario::take_from_sender<PublisherCap>(&scenario);
        let mut registry = test_scenario::take_shared<CertificateRegistry>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Issue first certificate
        let proof_hash = string::utf8(b"duplicate_proof_test");
        
        certificate::issue_certificate(
            &publisher_cap,
            &mut registry,
            proof_hash,
            string::utf8(b"2024-01-01T00:00:00Z"),
            string::utf8(b"2024-01-01T23:59:59Z"),
            1000,
            3,
            string::utf8(b"household_test"),
            string::utf8(b"blob_test"),
            USER1,
            &clock,
            ctx
        );

        // Try to issue second certificate with same proof_hash (should fail)
        certificate::issue_certificate(
            &publisher_cap,
            &mut registry,
            proof_hash, // Same proof hash
            string::utf8(b"2024-01-02T00:00:00Z"),
            string::utf8(b"2024-01-02T23:59:59Z"),
            2000,
            5,
            string::utf8(b"household_test2"),
            string::utf8(b"blob_test2"),
            USER2,
            &clock,
            ctx
        );

        // Clean up (won't reach here due to expected failure)
        test_scenario::return_to_sender(&scenario, publisher_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_kiosk_integration() {
        let mut scenario = test_scenario::begin(PUBLISHER);
        let ctx = test_scenario::ctx(&mut scenario);

        certificate::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, PUBLISHER);

        let publisher_cap = test_scenario::take_from_sender<PublisherCap>(&scenario);
        let mut registry = test_scenario::take_shared<CertificateRegistry>(&scenario);
        let transfer_policy = test_scenario::take_shared<TransferPolicy<Certificate>>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Issue a certificate to USER1
        certificate::issue_certificate(
            &publisher_cap,
            &mut registry,
            string::utf8(b"kiosk_test_proof"),
            string::utf8(b"2024-01-01T00:00:00Z"),
            string::utf8(b"2024-01-01T23:59:59Z"),
            2000,
            4,
            string::utf8(b"kiosk_household"),
            string::utf8(b"kiosk_blob"),
            USER1,
            &clock,
            ctx
        );

        test_scenario::next_tx(&mut scenario, USER1);

        // USER1 creates a kiosk and places certificate
        let (mut kiosk, kiosk_cap) = kiosk::new(ctx);
        let certificate = test_scenario::take_from_sender<Certificate>(&scenario);
        
        certificate::place_in_kiosk(&mut kiosk, &kiosk_cap, certificate, &clock, ctx);

        // List certificate for sale
        let certificate_id = *std::vector::borrow(kiosk::item_ids<Certificate>(&kiosk), 0);
        let price = 1000000; // 1 SUI

        certificate::list_for_sale(&mut kiosk, &kiosk_cap, certificate_id, price, ctx);

        test_scenario::next_tx(&mut scenario, USER2);

        // USER2 purchases the certificate
        let payment = coin::mint_for_testing<SUI>(price, ctx);
        
        certificate::purchase_from_kiosk(
            &mut kiosk,
            certificate_id,
            payment,
            &transfer_policy,
            &clock,
            ctx
        );

        test_scenario::next_tx(&mut scenario, USER2);

        // Verify USER2 now owns the certificate
        let purchased_certificate = test_scenario::take_from_sender<Certificate>(&scenario);
        let (cert_proof_hash, _, _, _, _, _, _, _, _, _) = certificate::get_certificate_info(&purchased_certificate);
        assert!(cert_proof_hash == string::utf8(b"kiosk_test_proof"), 0);

        // Clean up
        test_scenario::return_to_sender(&scenario, purchased_certificate);
        test_scenario::return_to_sender(&scenario, publisher_cap);
        test_scenario::return_shared(registry);
        test_scenario::return_shared(transfer_policy);
        sui::transfer::public_transfer(kiosk_cap, USER1);
        sui::transfer::public_share_object(kiosk);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_certificate_queries() {
        let mut scenario = test_scenario::begin(PUBLISHER);
        let ctx = test_scenario::ctx(&mut scenario);

        certificate::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, PUBLISHER);

        let publisher_cap = test_scenario::take_from_sender<PublisherCap>(&scenario);
        let mut registry = test_scenario::take_shared<CertificateRegistry>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Issue multiple certificates
        let proof_hashes = std::vector::empty<std::string::String>();
        std::vector::push_back(&mut proof_hashes, string::utf8(b"proof_1"));
        std::vector::push_back(&mut proof_hashes, string::utf8(b"proof_2"));
        std::vector::push_back(&mut proof_hashes, string::utf8(b"proof_3"));

        let i = 0;
        while (i < std::vector::length(&proof_hashes)) {
            let proof_hash = *std::vector::borrow(&proof_hashes, i);
            
            certificate::issue_certificate(
                &publisher_cap,
                &mut registry,
                proof_hash,
                string::utf8(b"2024-01-01T00:00:00Z"),
                string::utf8(b"2024-01-01T23:59:59Z"),
                1000 + (i as u64) * 500,
                3 + (i as u64),
                string::utf8(b"household_test"),
                string::utf8(b"blob_test"),
                USER1,
                &clock,
                ctx
            );
            
            i = i + 1;
        };

        // Verify total issued count
        assert!(certificate::get_total_issued(&registry) == 3, 0);

        // Verify each certificate exists
        assert!(certificate::is_certificate_issued(&registry, string::utf8(b"proof_1")), 1);
        assert!(certificate::is_certificate_issued(&registry, string::utf8(b"proof_2")), 2);
        assert!(certificate::is_certificate_issued(&registry, string::utf8(b"proof_3")), 3);

        // Verify non-existent certificate
        assert!(!certificate::is_certificate_issued(&registry, string::utf8(b"proof_nonexistent")), 4);

        // Clean up
        test_scenario::return_to_sender(&scenario, publisher_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_certificate_accessors() {
        let mut scenario = test_scenario::begin(PUBLISHER);
        let ctx = test_scenario::ctx(&mut scenario);

        // Create a test certificate directly
        let proof_hash = string::utf8(b"accessor_test_proof");
        let total_kwh = 1234;
        let seal_blob_id = string::utf8(b"accessor_blob_id");

        let certificate = certificate::create_test_certificate(proof_hash, total_kwh, ctx);

        // Test accessor functions
        assert!(certificate::get_proof_hash(&certificate) == proof_hash, 0);
        assert!(certificate::get_total_kwh(&certificate) == total_kwh, 1);
        assert!(certificate::get_seal_blob_id(&certificate) == seal_blob_id, 2);

        // Clean up
        sui::transfer::public_transfer(certificate, PUBLISHER);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = certificate::EInvalidMetadata)]
    fun test_invalid_metadata_rejection() {
        let mut scenario = test_scenario::begin(PUBLISHER);
        let ctx = test_scenario::ctx(&mut scenario);

        certificate::init_for_testing(ctx);
        test_scenario::next_tx(&mut scenario, PUBLISHER);

        let publisher_cap = test_scenario::take_from_sender<PublisherCap>(&scenario);
        let mut registry = test_scenario::take_shared<CertificateRegistry>(&scenario);
        let clock = clock::create_for_testing(ctx);

        // Try to issue certificate with empty proof_hash (should fail)
        certificate::issue_certificate(
            &publisher_cap,
            &mut registry,
            string::utf8(b""), // Empty proof hash
            string::utf8(b"2024-01-01T00:00:00Z"),
            string::utf8(b"2024-01-01T23:59:59Z"),
            1000,
            3,
            string::utf8(b"household_test"),
            string::utf8(b"blob_test"),
            USER1,
            &clock,
            ctx
        );

        // Clean up (won't reach here due to expected failure)
        test_scenario::return_to_sender(&scenario, publisher_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}