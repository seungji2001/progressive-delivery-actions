package com.portfolio.coupon.web;

import com.portfolio.coupon.fault.FaultInjectionInterceptor;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration(proxyBeanMethods = false)
public class WebConfig implements WebMvcConfigurer {

	private final FaultInjectionInterceptor faultInjectionInterceptor;

	public WebConfig(FaultInjectionInterceptor faultInjectionInterceptor) {
		this.faultInjectionInterceptor = faultInjectionInterceptor;
	}

	@Override
	public void addInterceptors(InterceptorRegistry registry) {
		registry.addInterceptor(this.faultInjectionInterceptor).addPathPatterns("/coupons/**");
	}

}
