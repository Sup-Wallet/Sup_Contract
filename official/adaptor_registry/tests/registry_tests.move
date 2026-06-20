#[test_only]
module adaptor_registry::registry_tests {
    use std::string;
    use sui::test_scenario as ts;
    use sui::clock;
    use adaptor_registry::registry::{Self, Registry};

    const PUBLISHER: address = @0xA1;
    const OTHER: address = @0xB2;

    fun svc(): string::String { string::utf8(b"0xpkg::adaptor::CetusAdaptor") }
    fun uri(): string::String { string::utf8(b"walrus://blob-1") }

    #[test]
    fun register_then_read() {
        let mut sc = ts::begin(PUBLISHER);
        registry::init_for_testing(sc.ctx());
        sc.next_tx(PUBLISHER);

        let mut reg = sc.take_shared<Registry>();
        let clk = clock::create_for_testing(sc.ctx());
        registry::register(&mut reg, @0xCE1, svc(), uri(), b"hash", &clk, sc.ctx());

        assert!(registry::is_listed(&reg, svc()), 0);
        let (pub_, pkg, _u, _h, ver, _t) = registry::listing(&reg, svc());
        assert!(pub_ == PUBLISHER, 1);
        assert!(pkg == @0xCE1, 2);
        assert!(ver == 1, 3);

        clock::destroy_for_testing(clk);
        ts::return_shared(reg);
        sc.end();
    }

    #[test]
    fun update_bumps_version() {
        let mut sc = ts::begin(PUBLISHER);
        registry::init_for_testing(sc.ctx());
        sc.next_tx(PUBLISHER);

        let mut reg = sc.take_shared<Registry>();
        let clk = clock::create_for_testing(sc.ctx());
        registry::register(&mut reg, @0xCE1, svc(), uri(), b"hash", &clk, sc.ctx());
        registry::update(&mut reg, svc(), @0xCE2, string::utf8(b"walrus://blob-2"), b"hash2", &clk, sc.ctx());

        let (_p, pkg, _u, _h, ver, _t) = registry::listing(&reg, svc());
        assert!(pkg == @0xCE2, 0);
        assert!(ver == 2, 1);

        clock::destroy_for_testing(clk);
        ts::return_shared(reg);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = registry::ENotPublisher)]
    fun non_publisher_cannot_update() {
        let mut sc = ts::begin(PUBLISHER);
        registry::init_for_testing(sc.ctx());
        sc.next_tx(PUBLISHER);

        let mut reg = sc.take_shared<Registry>();
        let clk = clock::create_for_testing(sc.ctx());
        registry::register(&mut reg, @0xCE1, svc(), uri(), b"hash", &clk, sc.ctx());
        sc.next_tx(OTHER);
        registry::update(&mut reg, svc(), @0xCE2, uri(), b"hash", &clk, sc.ctx());

        clock::destroy_for_testing(clk);
        ts::return_shared(reg);
        sc.end();
    }

    #[test]
    #[expected_failure(abort_code = registry::EAlreadyListed)]
    fun cannot_double_register() {
        let mut sc = ts::begin(PUBLISHER);
        registry::init_for_testing(sc.ctx());
        sc.next_tx(PUBLISHER);

        let mut reg = sc.take_shared<Registry>();
        let clk = clock::create_for_testing(sc.ctx());
        registry::register(&mut reg, @0xCE1, svc(), uri(), b"hash", &clk, sc.ctx());
        registry::register(&mut reg, @0xCE1, svc(), uri(), b"hash", &clk, sc.ctx());

        clock::destroy_for_testing(clk);
        ts::return_shared(reg);
        sc.end();
    }
}
