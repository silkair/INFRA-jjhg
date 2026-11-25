package me.jinjjahalgae.global.scheduler;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import me.jinjjahalgae.domain.contract.usecase.process.*;
import me.jinjjahalgae.domain.proof.usecase.schedule.CheckExpiredProofUseCase;
import me.jinjjahalgae.global.scheduler.processor.ContractJobProcessor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Slf4j
@Component
@RequiredArgsConstructor
public class ScheduleManager {

    private final EndOneOffContractUseCase endOneOffContractUseCase;
    private final VerifyOneOffContractSignatureUseCase verifyOneOffContractSignatureUseCase;
    private final CheckExpiredProofUseCase checkExpiredProofUseCase;

    private final ContractJobProcessor contractJobProcessor;
    /**
     * 5분마다 실행되는 스케줄러
     *
     * - 단건 계약 24시간 체크
     * - 단건 계약 서명검증
     * - 인증 24시간(만료) 체크
     */
    @Scheduled(cron = "0 */5 * * * *")
    // 파드가 여러 개면 락을 먼저 잡은 한 파드만 실행한다.
    // lockAtMostFor: 파드가 죽어 락을 못 풀어도 4분 뒤 자동 해제 (다음 실행 전에 풀리도록 5분보다 짧게)
    // lockAtLeastFor: 작업이 빨리 끝나도 30초는 락 유지 (파드 간 시계 차이로 다른 파드가 곧바로 다시 실행하는 것 방지)
    @SchedulerLock(name = "fiveMinuteSchedule", lockAtMostFor = "PT4M", lockAtLeastFor = "PT30S")
    @Transactional
    public void fiveMinuteSchedule() {
        log.info("[Scheduler] 5분 스케줄러 시작. 현재 UTC 시간: {}", Instant.now());

        // 단건 계약 24시간 체크
        endOneOffContractUseCase.execute();

        // 단건 계약 서명검증
        verifyOneOffContractSignatureUseCase.execute();

        // 인증 24시간(만료) 체크
        checkExpiredProofUseCase.execute(Instant.now());
    }

    /**
     * 매일 15:01 (UTC)에 실행되는 스케줄러 (KST 기준 다음날 00:01)
     *
     * - 시작일 확인 후 계약 시작
     * - 성공 실패를 판단 후 계약 종료
     *
     * 재시도
     * - 개별 유스케이스 마다 재시도 수행
     * - 3번 수행 후 최종 실패 시 로그 출력
     */
    @Scheduled(cron = "0 1 15 * * *" )
    @SchedulerLock(name = "daySchedule", lockAtMostFor = "PT30M", lockAtLeastFor = "PT1M")
    public void daySchedule() {
        log.info("[Scheduler] 하루 스케줄러 시작. 현재 UTC 시간: {}", Instant.now());

        // 시작일 확인 후 계약 시작
        contractJobProcessor.startContracts("start");

        // 성공 실패를 판단 후 계약 종료
        contractJobProcessor.endContracts("end");
    }
}
