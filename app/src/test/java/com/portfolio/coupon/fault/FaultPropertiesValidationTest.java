package com.portfolio.coupon.fault;

import org.junit.jupiter.api.Test;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

import static org.assertj.core.api.Assertions.assertThat;

class FaultPropertiesValidationTest {

	private final ApplicationContextRunner runner = new ApplicationContextRunner()
		.withUserConfiguration(FaultConfig.class);

	@Test
	void 범위_안의_값이면_기동() {
		this.runner.withPropertyValues("fault.rate=0.5")
			.run((context) -> assertThat(context).hasNotFailed()
				.getBean(FaultProperties.class)
				.extracting(FaultProperties::rate)
				.isEqualTo(0.5));
	}

	@Test
	void 범위_1을_초과하면_기동_실패() {
		this.runner.withPropertyValues("fault.rate=1.5").run((context) -> assertThat(context).hasFailed());
	}

	@Test
	void 음수면_기동_실패() {
		this.runner.withPropertyValues("fault.rate=-0.1").run((context) -> assertThat(context).hasFailed());
	}

	@Test
	void 지연이_10000ms_를_넘으면_기동_실패() {
		this.runner.withPropertyValues("fault.delay-ms=10001").run((context) -> assertThat(context).hasFailed());
	}

	@Test
	void 지연_범위_안이면_기동() {
		this.runner.withPropertyValues("fault.delay-ms=800")
			.run((context) -> assertThat(context).hasNotFailed()
				.getBean(FaultProperties.class)
				.extracting(FaultProperties::delayMs)
				.isEqualTo(800L));
	}

	@Configuration(proxyBeanMethods = false)
	@EnableConfigurationProperties(FaultProperties.class)
	static class FaultConfig {

	}

}
