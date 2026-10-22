package com.portfolio.coupon.fault;

public class FaultInjectedException extends RuntimeException {

	public FaultInjectedException() {
		super("의도적으로 주입된 장애입니다.");
	}

}
