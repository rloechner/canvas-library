import {
  Callout,
  Card,
  CardBody,
  CardHeader,
  Grid,
  H1,
  Pill,
  Row,
  Stack,
  Stat,
  Text,
} from "cursor/canvas";

/**
 * Fictional Northstar Analytics pricing canvas — sample for screenshots.
 */
export default function PricingGrid() {
  return (
    <Stack gap={24} style={{ padding: 28, maxWidth: 960 }}>
      <Stack gap={8}>
        <Row gap={8} align="center" wrap>
          <H1 style={{ margin: 0 }}>Pricing experiment</H1>
          <Pill tone="info">Northstar</Pill>
          <Pill tone="success">Variant B leading</Pill>
        </Row>
        <Text tone="secondary" size="small">
          Made-up A/B results for Canvas Library product shots
        </Text>
      </Stack>

      <Callout tone="success" title="Ship Variant B copy">
        “Ship decisions, not dashboards” + Start free is outperforming Talk to sales
        on free→paid without hurting Enterprise demos.
      </Callout>

      <Grid columns={3} gap={12}>
        <Stat value="4.1%" label="Paid conversion (B)" tone="success" />
        <Stat value="2.6%" label="Paid conversion (A)" />
        <Stat value="+58%" label="Relative lift" tone="success" />
      </Grid>

      <Grid columns={3} gap={16}>
        <Card>
          <CardHeader>Starter · $12</CardHeader>
          <CardBody>
            <Stack gap={6}>
              <Text>3 seats · core dashboards</Text>
              <Text tone="secondary" size="small">
                Best for solo PMs
              </Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader>Pro · $29</CardHeader>
          <CardBody>
            <Stack gap={6}>
              <Text>10 seats · shared boards</Text>
              <Text tone="secondary" size="small">
                Highlighted tier in Variant B
              </Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader>Team · $79</CardHeader>
          <CardBody>
            <Stack gap={6}>
              <Text>Unlimited · SSO + audit log</Text>
              <Text tone="secondary" size="small">
                Annual −20% toggle
              </Text>
            </Stack>
          </CardBody>
        </Card>
      </Grid>
    </Stack>
  );
}
