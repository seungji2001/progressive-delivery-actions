package com.portfolio.coupon.version;

import java.time.Instant;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class VersionController {

	private final VersionInfo versionInfo;

	public VersionController(VersionInfo versionInfo) {
		this.versionInfo = versionInfo;
	}

	@GetMapping("/version")
	public VersionResponse version() {
		return new VersionResponse(this.versionInfo.version(), this.versionInfo.commit(),
				this.versionInfo.startedAt(), this.versionInfo.hostname());
	}

	public record VersionResponse(String version, String commit, Instant startedAt, String hostname) {
	}

}
