package com.portfolio.coupon.coupon;

public class MinOrderAmountNotMetException extends RuntimeException {

	public MinOrderAmountNotMetException(long orderAmount, long minOrderAmount) {
		super("주문 금액 %d원이 최소 주문 금액 %d원보다 적습니다.".formatted(orderAmount, minOrderAmount));
	}

}
