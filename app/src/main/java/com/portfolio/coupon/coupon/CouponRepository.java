package com.portfolio.coupon.coupon;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.stereotype.Repository;

/**
 * 인메모리 저장소. 태스크·버전 간 데이터는 공유되지 않는다 (의도된 제약).
 */
@Repository
public class CouponRepository {

	private final Map<UUID, Coupon> store = new ConcurrentHashMap<>();

	public Coupon save(Coupon coupon) {
		this.store.put(coupon.couponId(), coupon);
		return coupon;
	}

	public Optional<Coupon> findById(UUID couponId) {
		return Optional.ofNullable(this.store.get(couponId));
	}

}
