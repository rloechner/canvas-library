import {
  Callout,
  Card,
  CardBody,
  CardHeader,
  Grid,
  H1,
  H2,
  Pill,
  Row,
  Stack,
  Stat,
  Text,
} from "cursor/canvas";

/**
 * Fictional Harbor Desk onboarding review — sample canvas for screenshots.
 */
export default function OnboardingReview() {
  return (
    <Stack gap={24} style={{ padding: 28, maxWidth: 960 }}>
      <Stack gap={8}>
        <Row gap={8} align="center" wrap>
          <H1 style={{ margin: 0 }}>Onboarding review</H1>
          <Pill tone="info">Harbor Desk</Pill>
          <Pill tone="neutral">Week of Jul 14</Pill>
        </Row>
        <Text tone="secondary" size="small">
          Fictional product sample · demo metrics only
        </Text>
      </Stack>

      <Callout tone="info" title="Stay the course on templates">
        Time-to-first-share is improving. Focus this sprint on the share prompt and
        prefilled cards — not a full first-run redesign.
      </Callout>

      <Grid columns={4} gap={12}>
        <Stat value="7m 40s" label="Median time to share" tone="success" />
        <Stat value="68%" label="SSO adoption" />
        <Stat value="22%" label="Drop at first share" tone="warning" />
        <Stat value="3" label="Template boards" />
      </Grid>

      <Grid columns="1.1fr 1fr" gap={16}>
        <Card>
          <CardHeader>What is working</CardHeader>
          <CardBody>
            <Stack gap={8}>
              <Text>• Sample “Team standup” board reduces blank-slate freeze</Text>
              <Text>• SSO path is ~40% faster than password create</Text>
              <Text>• Inline tips under the share button get clicks</Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader>Next experiments</CardHeader>
          <CardBody>
            <Stack gap={8}>
              <Text>1. Soft share prompt after 90s of editing</Text>
              <Text>2. Prefill three cards on first board</Text>
              <Text>3. Hide integrations until day 2</Text>
            </Stack>
          </CardBody>
        </Card>
      </Grid>

      <Stack gap={8}>
        <H2 style={{ margin: 0 }}>Decision</H2>
        <Text>
          Ship the share prompt this week. Park the mobile-specific first-run until
          desktop funnel is under 6 minutes.
        </Text>
      </Stack>
    </Stack>
  );
}
