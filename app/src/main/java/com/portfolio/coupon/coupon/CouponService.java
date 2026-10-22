package com.portfolio.coupon.coupon;

import java.time.Clock;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import com.portfolio.coupon.version.VersionInfo;

import org.springframework.stereotype.Service;

@Service
public class CouponService {

	/**
	 * v3: 회원 등급별 추가 할인(원). 등급은 userId 로 산출한 0~3.
	 */
	private static final Map<Integer, Long> GRADE_BONUS = Map.of(0, 0L, 1, 500L, 3, 1000L);

	private final DiscountPolicy discountPolicy;
	private final CouponRepository couponRepository;
	private final VersionInfo versionInfo;

	public CouponService(DiscountPolicy discountPolicy, CouponRepository couponRepository, VersionInfo versionInfo) {
		this.discountPolicy = discountPolicy;
		this.couponRepository = couponRepository;
		this.versionInfo = versionInfo;
	}

	public Coupon issue(String userId, long orderAmount) {
		long discountAmount = this.discountPolicy.discount(orderAmount) + GRADE_BONUS.get(gradeOf(userId));
		long finalAmount = Math.max(0, orderAmount - discountAmount);
		Coupon coupon = new Coupon(UUID.randomUUID(), userId, this.discountPolicy.type(), orderAmount,
				discountAmount, finalAmount, Instant.now(Clock.systemUTC()), this.versionInfo.version());
		return this.couponRepository.save(coupon);
	}

	static int gradeOf(String userId) {
		return Math.floorMod(userId.hashCode(), 4);
	}

	public Coupon get(UUID couponId) {
		return this.couponRepository.findById(couponId).orElseThrow(() -> new CouponNotFoundException(couponId));
	}

}
