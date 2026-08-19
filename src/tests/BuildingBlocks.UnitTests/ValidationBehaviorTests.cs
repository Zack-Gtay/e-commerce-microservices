using FluentValidation;
using FluentValidation.Results;
using MediatR;
using NSubstitute;

namespace BuildingBlocks.UnitTests;

/// <summary>
/// The MediatR pipeline behaviour that runs FluentValidation in front of every command.
/// Worth testing directly because it is shared cross-cutting infrastructure: a regression
/// here silently disables validation for every command in every service.
/// </summary>
public class ValidationBehaviorTests
{
    public record TestCommand(string Name) : ICommand<TestResult>;
    public record TestResult(bool Handled);

    private sealed class NameRequiredValidator : AbstractValidator<TestCommand>
    {
        public NameRequiredValidator() =>
            RuleFor(x => x.Name).NotEmpty().WithMessage("Name is required");
    }

    private sealed class NameLengthValidator : AbstractValidator<TestCommand>
    {
        public NameLengthValidator() =>
            RuleFor(x => x.Name).MinimumLength(5).WithMessage("Name is too short");
    }

    private static ValidationBehavior<TestCommand, TestResult> BehaviorWith(
        params IValidator<TestCommand>[] validators) => new(validators);

    [Fact]
    public async Task Calls_the_next_handler_when_validation_passes()
    {
        var next = Substitute.For<RequestHandlerDelegate<TestResult>>();
        next().Returns(new TestResult(Handled: true));

        var behavior = BehaviorWith(new NameRequiredValidator());

        var result = await behavior.Handle(new TestCommand("Zakaria"), next, CancellationToken.None);

        result.Handled.Should().BeTrue();
        await next.Received(1).Invoke();
    }

    [Fact]
    public async Task Throws_ValidationException_when_a_rule_fails()
    {
        var next = Substitute.For<RequestHandlerDelegate<TestResult>>();
        var behavior = BehaviorWith(new NameRequiredValidator());

        var act = async () => await behavior.Handle(new TestCommand(""), next, CancellationToken.None);

        await act.Should().ThrowAsync<ValidationException>();
    }

    [Fact]
    public async Task Short_circuits_the_pipeline_so_the_handler_never_runs_on_invalid_input()
    {
        var next = Substitute.For<RequestHandlerDelegate<TestResult>>();
        var behavior = BehaviorWith(new NameRequiredValidator());

        var act = async () => await behavior.Handle(new TestCommand(""), next, CancellationToken.None);
        await act.Should().ThrowAsync<ValidationException>();

        // The important half of the assertion: an invalid command must never reach the
        // handler, so no partial write can happen before the error surfaces.
        await next.DidNotReceive().Invoke();
    }

    [Fact]
    public async Task Aggregates_failures_across_every_registered_validator()
    {
        var next = Substitute.For<RequestHandlerDelegate<TestResult>>();
        var behavior = BehaviorWith(new NameRequiredValidator(), new NameLengthValidator());

        var act = async () => await behavior.Handle(new TestCommand(""), next, CancellationToken.None);

        var thrown = await act.Should().ThrowAsync<ValidationException>();
        thrown.Which.Errors.Should().HaveCount(2);
        thrown.Which.Errors.Select(e => e.ErrorMessage)
            .Should().BeEquivalentTo(["Name is required", "Name is too short"]);
    }

    [Fact]
    public async Task Passes_through_when_no_validator_is_registered_for_the_command()
    {
        var next = Substitute.For<RequestHandlerDelegate<TestResult>>();
        next().Returns(new TestResult(Handled: true));

        var behavior = BehaviorWith(); // no validators

        var result = await behavior.Handle(new TestCommand(""), next, CancellationToken.None);

        result.Handled.Should().BeTrue();
        await next.Received(1).Invoke();
    }

    [Fact]
    public void Surfaces_the_property_name_on_each_failure_for_the_ProblemDetails_payload()
    {
        // CustomExceptionHandler serialises ValidationException.Errors into the
        // "ValidationErrors" extension of the RFC 7807 response, so the per-property
        // metadata has to survive.
        var failures = new NameRequiredValidator().Validate(new TestCommand("")).Errors;

        failures.Should().ContainSingle()
            .Which.Should().BeOfType<ValidationFailure>()
            .Which.PropertyName.Should().Be(nameof(TestCommand.Name));
    }
}
