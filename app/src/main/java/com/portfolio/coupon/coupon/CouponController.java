package com.portfolio.coupon.coupon;

import java.net.URI;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/coupons")
public class CouponController {

	private final CouponService couponService;

	public CouponController(CouponService couponService) {
		this.couponService = couponService;
	}

	@PostMapping("/issue")
	public ResponseEntity<Coupon> issue(@Valid @RequestBody IssueCouponRequest request) {
		Coupon coupon = this.couponService.issue(request.userId(), request.orderAmount());
		return ResponseEntity.created(URI.create("/coupons/" + coupon.couponId())).body(coupon);
	}

	@GetMapping("/{couponId}")
	public Coupon get(@PathVariable UUID couponId) {
		return this.couponService.get(couponId);
	}

	public record IssueCouponRequest(@NotBlank String userId, @NotNull @Positive Long orderAmount) {
	}

}
