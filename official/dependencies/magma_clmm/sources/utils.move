module magma_clmm::utils;

use std::string;

public fun str(mut n: u64): string::String {
    if (n == 0) {
        return string::utf8(b"0")
    };
    let mut s = vector::empty<u8>();
    while (n > 0) {
        let c = (n % 10) as u8;
        n = n / 10;
        s.push_back(c + 48);
    };
    s.reverse();
    string::utf8(s)
}
