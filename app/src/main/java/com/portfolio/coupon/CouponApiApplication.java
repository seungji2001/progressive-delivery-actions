package com.portfolio.coupon;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class CouponApiApplication {

	public static void main(String[] args) {
		SpringApplication.run(CouponApiApplication.class, args);
	}

}
