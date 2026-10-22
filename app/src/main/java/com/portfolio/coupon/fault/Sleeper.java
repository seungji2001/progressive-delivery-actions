package com.portfolio.coupon.fault;

/**
 * 지연 주입용 sleep 추상화. 테스트에서 실제로 기다리지 않도록 교체한다.
 */
@FunctionalInterface
public interface Sleeper {

	void sleep(long millis) throws InterruptedException;

}
