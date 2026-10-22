package com.portfolio.coupon.coupon;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class FixedAmountDiscountPolicyTest {

	private final FixedAmountDiscountPolicy policy = new FixedAmountDiscountPolicy(new CouponProperties(3000, 10000));

	@Test
	void 최소_주문금액_미만이면_예외() {
		assertThatThrownBy(() -> this.policy.discount(9999)).isInstanceOf(MinOrderAmountNotMetException.class);
	}

	@Test
	void 최소_주문금액과_같으면_할인() {
		assertThat(this.policy.discount(10000)).isEqualTo(3000);
	}

	@Test
	void 최소_주문금액_초과면_정액_할인() {
		assertThat(this.policy.discount(25000)).isEqualTo(3000);
	}

	@Test
	void 할인액이_주문금액보다_크면_주문금액까지만_할인() {
		FixedAmountDiscountPolicy bigDiscount = new FixedAmountDiscountPolicy(new CouponProperties(50000, 0));
		assertThat(bigDiscount.discount(20000)).isEqualTo(20000);
	}

	@Test
	void 할인_타입은_FIXED() {
		assertThat(this.policy.type()).isEqualTo("FIXED");
	}

}
