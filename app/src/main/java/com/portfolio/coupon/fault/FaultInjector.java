package com.portfolio.coupon.fault;

import java.util.concurrent.ThreadLocalRandom;
import java.util.function.DoubleSupplier;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * FAULT_RATE 확률로 장애 여부를 판정하고, FAULT_DELAY_MS 만큼 응답을 지연시킨다.
 * 지연과 에러는 서로 독립적으로 동작한다. 난수 소스와 sleep 은 테스트에서 고정할 수 있도록 주입받는다.
 */
@Component
public class FaultInjector {

	private final double rate;
	private final long delayMs;
	private final DoubleSupplier random;
	private final Sleeper sleeper;

	@Autowired
	public FaultInjector(FaultProperties properties) {
		this(properties, () -> ThreadLocalRandom.current().nextDouble(), Thread::sleep);
	}

	FaultInjector(FaultProperties properties, DoubleSupplier random) {
		this(properties, random, Thread::sleep);
	}

	FaultInjector(FaultProperties properties, DoubleSupplier random, Sleeper sleeper) {
		this.rate = properties.rate();
		this.delayMs = properties.delayMs();
		this.random = random;
		this.sleeper = sleeper;
	}

	public boolean shouldFail() {
		return this.rate > 0 && this.random.getAsDouble() < this.rate;
	}

	/**
	 * @return 실제로 지연한 시간(ms). 지연 설정이 없으면 0
	 */
	public long delay() {
		if (this.delayMs <= 0) {
			return 0;
		}
		try {
			this.sleeper.sleep(this.delayMs);
		}
		catch (InterruptedException ex) {
			Thread.currentThread().interrupt();
		}
		return this.delayMs;
	}

	public double rate() {
		return this.rate;
	}

}
