package com.portfolio.coupon.coupon;

import org.springframework.stereotype.Component;

/**
 * v2 정률 할인. 원 단위 절사, 최대 할인 금액 상한을 둔다.
 */
@Component
public class PercentageDiscountPolicy implements DiscountPolicy {

	private final CouponProperties properties;

	public PercentageDiscountPolicy(CouponProperties properties) {
		this.properties = properties;
	}

	@Override
	public long discount(long orderAmount) {
		if (orderAmount < this.properties.minOrderAmount()) {
			throw new MinOrderAmountNotMetException(orderAmount, this.properties.minOrderAmount());
		}
		long discount = orderAmount * this.properties.percent() / 100;
		return Math.min(discount, this.properties.maxDiscountAmount());
	}

	@Override
	public String type() {
		return "PERCENTAGE";
	}

}
