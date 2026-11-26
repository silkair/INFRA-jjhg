package me.jinjjahalgae.domain.participation.usecase.create.supervisor;

import me.jinjjahalgae.domain.participation.usecase.create.contractor.dto.CreateContractorParticipationRequest;

public interface CreateSupervisorParticipationUseCase {
    void execute(Long contractId, CreateContractorParticipationRequest request, Long userId);
}
