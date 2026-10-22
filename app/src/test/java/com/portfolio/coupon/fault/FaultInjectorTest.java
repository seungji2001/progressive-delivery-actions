package com.portfolio.coupon.fault;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class FaultInjectorTest {

	@Test
	void rate_0이면_항상_통과() {
		FaultInjector injector = new FaultInjector(new FaultProperties(0.0), () -> 0.0);
		assertThat(injector.shouldFail()).isFalse();
	}

	@Test
	void rate_1이면_항상_실패() {
		FaultInjector injector = new FaultInjector(new FaultProperties(1.0), () -> 0.9999);
		assertThat(injector.shouldFail()).isTrue();
	}

	@Test
	void 난수가_rate_미만이면_실패() {
		FaultInjector injector = new FaultInjector(new FaultProperties(0.3), () -> 0.2999);
		assertThat(injector.shouldFail()).isTrue();
	}

	@Test
	void 난수가_rate와_같거나_크면_통과() {
		FaultInjector injector = new FaultInjector(new FaultProperties(0.3), () -> 0.3);
		assertThat(injector.shouldFail()).isFalse();
	}

}
