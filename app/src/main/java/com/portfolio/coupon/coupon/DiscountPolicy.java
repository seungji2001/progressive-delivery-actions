package com.portfolio.coupon.coupon;

/**
 * 할인 정책. v1(정액) → v2(정률) 릴리즈는 이 구현체 교체만으로 끝나도록 분리한다.
 */
public interface DiscountPolicy {

	/**
	 * @param orderAmount 주문 금액(원)
	 * @return 할인 금액(원)
	 * @throws MinOrderAmountNotMetException 최소 주문 금액 미만일 때
	 */
	long discount(long orderAmount);

	String type();

}
