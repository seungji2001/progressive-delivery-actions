package com.portfolio.coupon.coupon;

import org.springframework.stereotype.Component;

/**
 * v1 정액 할인. 할인액이 주문 금액을 넘으면 주문 금액까지만 할인한다.
 */
@Component
public class FixedAmountDiscountPolicy implements DiscountPolicy {

	private final CouponProperties properties;

	public FixedAmountDiscountPolicy(CouponProperties properties) {
		this.properties = properties;
	}

	@Override
	public long discount(long orderAmount) {
		if (orderAmount < this.properties.minOrderAmount()) {
			throw new MinOrderAmountNotMetException(orderAmount, this.properties.minOrderAmount());
		}
		return Math.min(this.properties.fixedAmount(), orderAmount);
	}

	@Override
	public String type() {
		return "FIXED";
	}

}
