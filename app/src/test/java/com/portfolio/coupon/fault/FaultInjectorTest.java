package com.portfolio.coupon.fault;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class FaultInjectorTest {

	@Test
	void rate_0이면_항상_통과() {
		FaultInjector injector = new FaultInjector(new FaultProperties(0.0, 0), () -> 0.0);
		assertThat(injector.shouldFail()).isFalse();
	}

	@Test
	void rate_1이면_항상_실패() {
		FaultInjector injector = new FaultInjector(new FaultProperties(1.0, 0), () -> 0.9999);
		assertThat(injector.shouldFail()).isTrue();
	}

	@Test
	void 난수가_rate_미만이면_실패() {
		FaultInjector injector = new FaultInjector(new FaultProperties(0.3, 0), () -> 0.2999);
		assertThat(injector.shouldFail()).isTrue();
	}

	@Test
	void 난수가_rate와_같거나_크면_통과() {
		FaultInjector injector = new FaultInjector(new FaultProperties(0.3, 0), () -> 0.3);
		assertThat(injector.shouldFail()).isFalse();
	}

	@Test
	void delay_설정이_없으면_기다리지_않는다() {
		long[] slept = { -1 };
		FaultInjector injector = new FaultInjector(new FaultProperties(0.0, 0), () -> 1.0, (ms) -> slept[0] = ms);
		assertThat(injector.delay()).isZero();
		assertThat(slept[0]).isEqualTo(-1);
	}

	@Test
	void delay_설정만큼_sleep_을_호출한다() {
		long[] slept = { -1 };
		FaultInjector injector = new FaultInjector(new FaultProperties(0.0, 800), () -> 1.0, (ms) -> slept[0] = ms);
		assertThat(injector.delay()).isEqualTo(800);
		assertThat(slept[0]).isEqualTo(800);
	}

	@Test
	void 지연과_에러는_독립적이다() {
		FaultInjector injector = new FaultInjector(new FaultProperties(0.0, 800), () -> 0.0, (ms) -> { });
		injector.delay();
		assertThat(injector.shouldFail()).isFalse();
	}

}
