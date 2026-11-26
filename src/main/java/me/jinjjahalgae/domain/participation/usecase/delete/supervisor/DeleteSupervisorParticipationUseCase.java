package me.jinjjahalgae.domain.participation.usecase.delete.supervisor;


public interface DeleteSupervisorParticipationUseCase {
    void execute(Long contractId, Long userId);
}
