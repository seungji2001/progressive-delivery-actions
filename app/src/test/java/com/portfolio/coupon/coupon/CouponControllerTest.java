package com.portfolio.coupon.coupon;

import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import com.portfolio.coupon.fault.FaultInjector;
import com.portfolio.coupon.fault.FaultProperties;
import com.portfolio.coupon.version.AppProperties;
import com.portfolio.coupon.version.VersionInfo;

import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.matchesPattern;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(properties = "app.version=v-test")
@Import({ CouponService.class, CouponRepository.class, PercentageDiscountPolicy.class, VersionInfo.class,
		FaultInjector.class })
@EnableConfigurationProperties({ CouponProperties.class, AppProperties.class, FaultProperties.class })
class CouponControllerTest {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void 발급하면_201과_Location() throws Exception {
		this.mockMvc.perform(issue("{\"userId\":\"u-1\",\"orderAmount\":25000}"))
			.andExpect(status().isCreated())
			.andExpect(header().string("Location", matchesPattern("/coupons/[0-9a-f-]{36}")))
			.andExpect(header().string("X-App-Version", "v-test"))
			.andExpect(jsonPath("$.discountType").value("PERCENTAGE"))
			.andExpect(jsonPath("$.discountAmount").value(3000))
			.andExpect(jsonPath("$.finalAmount").value(22000))
			.andExpect(jsonPath("$.appVersion").value("v-test"));
	}

	@Test
	void 발급한_쿠폰을_조회한다() throws Exception {
		String location = this.mockMvc.perform(issue("{\"userId\":\"u-1\",\"orderAmount\":25000}"))
			.andReturn()
			.getResponse()
			.getHeader("Location");

		this.mockMvc.perform(get(location))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.userId").value("u-1"));
	}

	@Test
	void 검증_실패는_400_ProblemDetail() throws Exception {
		this.mockMvc.perform(issue("{\"userId\":\" \",\"orderAmount\":-1}"))
			.andExpect(status().isBadRequest())
			.andExpect(header().string("Content-Type", MediaType.APPLICATION_PROBLEM_JSON_VALUE))
			.andExpect(header().string("X-App-Version", "v-test"));
	}

	@Test
	void 최소_주문금액_미만은_422() throws Exception {
		this.mockMvc.perform(issue("{\"userId\":\"u-1\",\"orderAmount\":5000}"))
			.andExpect(status().isUnprocessableContent())
			.andExpect(jsonPath("$.type", endsWith("/min-order-amount-not-met")))
			.andExpect(header().string("X-App-Version", "v-test"));
	}

	@Test
	void 없는_쿠폰은_404() throws Exception {
		this.mockMvc.perform(get("/coupons/00000000-0000-0000-0000-000000000000"))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.type", endsWith("/coupon-not-found")))
			.andExpect(header().string("X-App-Version", "v-test"));
	}

	private static org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder issue(String body) {
		return post("/coupons/issue").contentType(MediaType.APPLICATION_JSON).content(body);
	}

}
