package com.portfolio.coupon.web;

import java.net.URI;

import com.portfolio.coupon.coupon.CouponNotFoundException;
import com.portfolio.coupon.coupon.MinOrderAmountNotMetException;
import com.portfolio.coupon.fault.FaultInjectedException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * 모든 오류를 RFC 7807 ProblemDetail 로 통일한다.
 * 검증 실패(400)는 ResponseEntityExceptionHandler 기본 처리에 맡긴다.
 */
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

	private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

	private static final String TYPE_BASE = "https://progressive-delivery-actions/problems/";

	@ExceptionHandler(CouponNotFoundException.class)
	ProblemDetail handleNotFound(CouponNotFoundException ex) {
		return problem(HttpStatus.NOT_FOUND, "coupon-not-found", ex.getMessage());
	}

	@ExceptionHandler(MinOrderAmountNotMetException.class)
	ProblemDetail handlePolicyViolation(MinOrderAmountNotMetException ex) {
		return problem(HttpStatus.UNPROCESSABLE_CONTENT, "min-order-amount-not-met", ex.getMessage());
	}

	@ExceptionHandler(FaultInjectedException.class)
	ProblemDetail handleFaultInjected(FaultInjectedException ex) {
		return problem(HttpStatus.INTERNAL_SERVER_ERROR, "fault-injected", ex.getMessage());
	}

	@ExceptionHandler(Exception.class)
	ProblemDetail handleUnexpected(Exception ex) {
		log.error("Unexpected error", ex);
		return problem(HttpStatus.INTERNAL_SERVER_ERROR, "internal-error", "예기치 못한 오류가 발생했습니다.");
	}

	private static ProblemDetail problem(HttpStatus status, String type, String detail) {
		ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
		problem.setType(URI.create(TYPE_BASE + type));
		return problem;
	}

}
