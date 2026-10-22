package com.portfolio.coupon.version;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 배포 파이프라인이 주입하는 버전 정보 (APP_VERSION, GIT_SHA).
 */
@ConfigurationProperties("app")
public record AppProperties(String version, String commit) {
}
