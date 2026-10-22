package com.portfolio.coupon;

import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureRestTestClient;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * 실제 서버를 띄워 ALB 헬스체크 경로와 발급→조회 왕복을 검증한다.
 */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT, properties = "app.version=v-smoke")
@AutoConfigureRestTestClient
class CouponApiSmokeTest {

	@Autowired
	private RestTestClient client;

	@Test
	void readiness는_UP() {
		this.client.get().uri("/health/readiness").exchange().expectStatus().isOk().expectBody()
			.jsonPath("$.status").isEqualTo("UP");
	}

	@Test
	void version_응답_형식() {
		this.client.get().uri("/version").exchange().expectStatus().isOk()
			.expectHeader().valueEquals("X-App-Version", "v-smoke")
			.expectBody()
			.jsonPath("$.version").isEqualTo("v-smoke")
			.jsonPath("$.commit").exists()
			.jsonPath("$.startedAt").exists()
			.jsonPath("$.hostname").exists();
	}

	@Test
	void 발급_후_조회_왕복() {
		String location = this.client.post().uri("/coupons/issue").contentType(MediaType.APPLICATION_JSON)
			.body("{\"userId\":\"u-1\",\"orderAmount\":25000}")
			.exchange()
			.expectStatus().isEqualTo(HttpStatus.CREATED)
			.returnResult(String.class)
			.getResponseHeaders()
			.getLocation()
			.toString();

		this.client.get().uri(location).exchange().expectStatus().isOk().expectBody()
			.jsonPath("$.finalAmount").isEqualTo(22000);
	}

}
