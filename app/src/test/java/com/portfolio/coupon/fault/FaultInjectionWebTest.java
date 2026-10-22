package com.portfolio.coupon.fault;

import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import com.portfolio.coupon.coupon.CouponProperties;
import com.portfolio.coupon.coupon.CouponRepository;
import com.portfolio.coupon.coupon.CouponService;
import com.portfolio.coupon.coupon.FixedAmountDiscountPolicy;
import com.portfolio.coupon.version.AppProperties;
import com.portfolio.coupon.version.VersionInfo;

import static org.hamcrest.Matchers.endsWith;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(properties = { "fault.rate=1.0", "app.version=v-fault" })
@Import({ CouponService.class, CouponRepository.class, FixedAmountDiscountPolicy.class, VersionInfo.class,
		FaultInjector.class })
@EnableConfigurationProperties({ CouponProperties.class, AppProperties.class, FaultProperties.class })
class FaultInjectionWebTest {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void 쿠폰_API는_500_fault_injected() throws Exception {
		this.mockMvc
			.perform(post("/coupons/issue").contentType(MediaType.APPLICATION_JSON)
				.content("{\"userId\":\"u-1\",\"orderAmount\":25000}"))
			.andExpect(status().isInternalServerError())
			.andExpect(jsonPath("$.type", endsWith("/fault-injected")))
			.andExpect(header().string("X-App-Version", "v-fault"));
	}

	@Test
	void version은_장애_주입_대상이_아니다() throws Exception {
		this.mockMvc.perform(get("/version"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.version").value("v-fault"));
	}

}
