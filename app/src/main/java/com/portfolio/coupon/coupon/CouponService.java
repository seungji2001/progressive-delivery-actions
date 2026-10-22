package com.portfolio.coupon.coupon;

import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

import com.portfolio.coupon.version.VersionInfo;

import org.springframework.stereotype.Service;

@Service
public class CouponService {

	private final DiscountPolicy discountPolicy;
	private final CouponRepository couponRepository;
	private final VersionInfo versionInfo;

	public CouponService(DiscountPolicy discountPolicy, CouponRepository couponRepository, VersionInfo versionInfo) {
		this.discountPolicy = discountPolicy;
		this.couponRepository = couponRepository;
		this.versionInfo = versionInfo;
	}

	public Coupon issue(String userId, long orderAmount) {
		long discountAmount = this.discountPolicy.discount(orderAmount);
		long finalAmount = Math.max(0, orderAmount - discountAmount);
		Coupon coupon = new Coupon(UUID.randomUUID(), userId, this.discountPolicy.type(), orderAmount,
				discountAmount, finalAmount, Instant.now(Clock.systemUTC()), this.versionInfo.version());
		return this.couponRepository.save(coupon);
	}

	public Coupon get(UUID couponId) {
		return this.couponRepository.findById(couponId).orElseThrow(() -> new CouponNotFoundException(couponId));
	}

}
