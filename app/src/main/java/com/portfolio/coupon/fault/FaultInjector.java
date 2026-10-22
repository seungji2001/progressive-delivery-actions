package com.portfolio.coupon.fault;

import java.util.concurrent.ThreadLocalRandom;
import java.util.function.DoubleSupplier;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * FAULT_RATE 확률로 장애 여부를 판정한다. 난수 소스는 테스트에서 고정할 수 있도록 주입받는다.
 */
@Component
public class FaultInjector {

	private final double rate;
	private final DoubleSupplier random;

	@Autowired
	public FaultInjector(FaultProperties properties) {
		this(properties, () -> ThreadLocalRandom.current().nextDouble());
	}

	FaultInjector(FaultProperties properties, DoubleSupplier random) {
		this.rate = properties.rate();
		this.random = random;
	}

	public boolean shouldFail() {
		return this.rate > 0 && this.random.getAsDouble() < this.rate;
	}

	public double rate() {
		return this.rate;
	}

}
