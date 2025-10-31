// FILE: tests/sKWH_tests.move
#[test_only]
module greenshare::sKWH_tests {
    use greenshare::sKWH::{Self, AdminCap, sKWHRegistry, sKWH, create_test_token};
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string;

    const ADMIN: address = @0xA;
    const USER1: address = @0xB;
    const USER2: address = @0xC;
    const ROFL_ENCLAVE: address = @0xD;

    #[test]
    fun test_init_module() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize the module
        sKWH::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);

        // Check if admin cap was created
        assert!(test_scenario::has_most_recent_for_sender<AdminCap>(&scenario), 0);
        
        // Check if registry was created and shared
        test_scenario::next_tx(&mut scenario, USER1);
        assert!(test_scenario::has_most_recent_shared<sKWHRegistry>(), 1);

        test_scenario::end(scenario);
    }

    #[test]
    fun test_mint_skwh_tokens() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Setup
        sKWH::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);

        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut registry = test_scenario::take_shared<sKWHRegistry>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1700000000000); // Set timestamp

        // Mint sKWH tokens
        let certificate_id = string::utf8(b"cert_001");
        let kwh_amount = 100000; // 100.0 kWh (scaled by 1000)
        let proof_data = b"mock_proof_data";

        let skwh_coin = sKWH::mint_skwh(
            &admin_cap,
            &mut registry,
            certificate_id,
            kwh_amount,
            *proof_data,
            string::utf8(b"https://walrus.space/blob123"),
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify the minted coin
        assert!(coin::value(&skwh_coin) == kwh_amount, 2);

        // Check registry stats
        let (total_supply, total_certificates) = sKWH::get_registry_stats(&registry);
        assert!(total_supply == kwh_amount, 3);
        assert!(total_certificates == 1, 4);

        // Transfer coin to user
        transfer::public_transfer(skwh_coin, USER1);

        // Cleanup
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_burn_skwh_for_bridging() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Setup
        sKWH::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);

        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut registry = test_scenario::take_shared<sKWHRegistry>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1700000000000);

        // Mint some tokens first
        let certificate_id = string::utf8(b"cert_burn_001");
        let kwh_amount = 50000; // 50.0 kWh
        let proof_data = b"mock_proof_data";

        let skwh_coin = sKWH::mint_skwh(
            &admin_cap,
            &mut registry,
            certificate_id,
            kwh_amount,
            *proof_data,
            string::utf8(b"https://walrus.space/blob456"),
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Transfer to user
        transfer::public_transfer(skwh_coin, USER1);
        test_scenario::next_tx(&mut scenario, USER1);

        // User burns tokens for bridging
        let skwh_coin = test_scenario::take_from_sender<Coin<sKWH>>(&scenario);
        let burn_amount = 30000; // 30.0 kWh
        let remaining_coin = coin::split(&mut skwh_coin, burn_amount, test_scenario::ctx(&mut scenario));

        let bridge_request = sKWH::burn_for_bridge(
            &mut registry,
            remaining_coin,
            string::utf8(b"0x742d35cc6cf004b4d6e8b0b1c5b2e7a5"),
            48899, // Zircuit chain ID
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Verify bridge request
        let (request_id, amount, recipient, chain_id, burn_timestamp) = sKWH::get_bridge_request_info(&bridge_request);
        assert!(amount == burn_amount, 5);
        assert!(chain_id == 48899, 6);
        assert!(burn_timestamp > 0, 7);

        // Check remaining coin
        assert!(coin::value(&skwh_coin) == kwh_amount - burn_amount, 8);

        // Cleanup
        transfer::public_transfer(skwh_coin, USER1);
        transfer::public_transfer(bridge_request, USER1);
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_transfer_skwh_tokens() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Setup
        sKWH::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);

        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut registry = test_scenario::take_shared<sKWHRegistry>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1700000000000);

        // Mint tokens
        let certificate_id = string::utf8(b"cert_transfer_001");
        let kwh_amount = 75000; // 75.0 kWh
        let proof_data = b"mock_proof_data";

        let skwh_coin = sKWH::mint_skwh(
            &admin_cap,
            &mut registry,
            certificate_id,
            kwh_amount,
            *proof_data,
            string::utf8(b"https://walrus.space/blob789"),
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Transfer to USER1
        transfer::public_transfer(skwh_coin, USER1);
        test_scenario::next_tx(&mut scenario, USER1);

        // USER1 transfers some to USER2
        let skwh_coin = test_scenario::take_from_sender<Coin<sKWH>>(&scenario);
        let transfer_amount = 25000; // 25.0 kWh
        let transfer_coin = coin::split(&mut skwh_coin, transfer_amount, test_scenario::ctx(&mut scenario));
        
        transfer::public_transfer(transfer_coin, USER2);
        transfer::public_transfer(skwh_coin, USER1);

        // Verify balances
        test_scenario::next_tx(&mut scenario, USER1);
        let user1_coin = test_scenario::take_from_sender<Coin<sKWH>>(&scenario);
        assert!(coin::value(&user1_coin) == kwh_amount - transfer_amount, 9);
        test_scenario::return_to_sender(&scenario, user1_coin);

        test_scenario::next_tx(&mut scenario, USER2);
        let user2_coin = test_scenario::take_from_sender<Coin<sKWH>>(&scenario);
        assert!(coin::value(&user2_coin) == transfer_amount, 10);
        test_scenario::return_to_sender(&scenario, user2_coin);

        // Cleanup
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = sKWH::ECertificateAlreadyExists)]
    fun test_prevent_duplicate_certificate() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Setup
        sKWH::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);

        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut registry = test_scenario::take_shared<sKWHRegistry>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1700000000000);

        let certificate_id = string::utf8(b"duplicate_cert");
        let kwh_amount = 50000;
        let proof_data = b"mock_proof_data";

        // Mint first time - should succeed
        let skwh_coin1 = sKWH::mint_skwh(
            &admin_cap,
            &mut registry,
            certificate_id,
            kwh_amount,
            *proof_data,
            string::utf8(b"https://walrus.space/blob1"),
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Try to mint with same certificate ID - should fail
        let skwh_coin2 = sKWH::mint_skwh(
            &admin_cap,
            &mut registry,
            certificate_id,
            kwh_amount,
            *proof_data,
            string::utf8(b"https://walrus.space/blob2"),
            &clock,
            test_scenario::ctx(&mut scenario)
        );

        // Cleanup (won't reach here due to expected failure)
        transfer::public_transfer(skwh_coin1, ADMIN);
        transfer::public_transfer(skwh_coin2, ADMIN);
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_emergency_pause_functionality() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Setup
        sKWH::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);

        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut registry = test_scenario::take_shared<sKWHRegistry>(&scenario);

        // Pause the contract
        sKWH::set_paused(&admin_cap, &mut registry, true);
        assert!(sKWH::is_paused(&registry), 11);

        // Unpause the contract
        sKWH::set_paused(&admin_cap, &mut registry, false);
        assert!(!sKWH::is_paused(&registry), 12);

        // Cleanup
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_certificate_retrieval() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Setup
        sKWH::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);

        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut registry = test_scenario::take_shared<sKWHRegistry>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1700000000000);

        // Mint multiple certificates
        let cert_ids = vector[
            string::utf8(b"cert_001"),
            string::utf8(b"cert_002"),
            string::utf8(b"cert_003")
        ];

        let mut i = 0;
        while (i < vector::length(&cert_ids)) {
            let cert_id = *vector::borrow(&cert_ids, i);
            let kwh_amount = 10000 * (i + 1); // Different amounts
            let proof_data = b"mock_proof_data";

            let skwh_coin = sKWH::mint_skwh(
                &admin_cap,
                &mut registry,
                cert_id,
                kwh_amount,
                *proof_data,
                string::utf8(b"https://walrus.space/blob"),
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            transfer::public_transfer(skwh_coin, USER1);
            i = i + 1;
        };

        // Check if certificates exist
        let cert_id = string::utf8(b"cert_002");
        assert!(sKWH::certificate_exists(&registry, cert_id), 13);

        let non_existent = string::utf8(b"cert_999");
        assert!(!sKWH::certificate_exists(&registry, non_existent), 14);

        // Cleanup
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_registry_statistics() {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Setup
        sKWH::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);

        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut registry = test_scenario::take_shared<sKWHRegistry>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1700000000000);

        // Initial stats should be zero
        let (initial_supply, initial_certs) = sKWH::get_registry_stats(&registry);
        assert!(initial_supply == 0, 15);
        assert!(initial_certs == 0, 16);

        // Mint some certificates
        let amounts = vector[10000, 20000, 30000]; // 10, 20, 30 kWh
        let total_expected = 60000;

        let mut i = 0;
        while (i < vector::length(&amounts)) {
            let amount = *vector::borrow(&amounts, i);
            let cert_id = string::utf8(b"stat_cert_");
            string::append(&mut cert_id, string::utf8(std::bcs::to_bytes(&i)));
            
            let skwh_coin = sKWH::mint_skwh(
                &admin_cap,
                &mut registry,
                cert_id,
                amount,
                b"mock_proof_data",
                string::utf8(b"https://walrus.space/blob"),
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            transfer::public_transfer(skwh_coin, USER1);
            i = i + 1;
        };

        // Check updated stats
        let (final_supply, final_certs) = sKWH::get_registry_stats(&registry);
        assert!(final_supply == total_expected, 17);
        assert!(final_certs == 3, 18);

        // Cleanup
        test_scenario::return_to_sender(&scenario, admin_cap);
        test_scenario::return_shared(registry);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}